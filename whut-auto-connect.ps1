# ============================================================
#  WHUT 校園網自動連接（PowerShell，無需瀏覽器）
#  ============================================================
#  適用：WHUT-DORM（宿舍網）／WHUT-WLAN（無線），武漢理工 深瀾 Web 認證。
#
#  原理：
#    未認證時，出口閘道會把 http 請求「重定向」到認證頁，
#    本腳本自動解析閘道位址與 nasId，再 POST 帳號密碼到 /api/account/login。
#
#  用法：
#    首次設定        ： 複製 config.example.ps1 為 config.ps1，填入帳號密碼
#    手動執行一次    ： powershell -ExecutionPolicy Bypass -File .\whut-auto-connect.ps1
#    常駐自動重連    ： powershell -ExecutionPolicy Bypass -File .\whut-auto-connect.ps1 -Loop
#    自訂檢測間隔    ： powershell -ExecutionPolicy Bypass -File .\whut-auto-connect.ps1 -Loop -IntervalMinutes 60 -RetrySeconds 60
#    開機自動執行    ： 以系統管理員執行 .\setup-task.ps1（見 README.md）
# ============================================================

param(
    [string]$Username     = '',            # 上網帳號（留空則從 config.ps1 讀取）
    [string]$Password     = '',            # 上網密碼（留空則從 config.ps1 讀取）
    [switch]$Loop,                         # 常駐監聽、斷線自動重連
    [int]$IntervalMinutes = 60,            # 已在線時，每 N 分鐘檢測一次
    [int]$RetrySeconds    = 60,            # 未認證／未連上時，每 N 秒重試
    [string]$LogFile      = ''             # 選填：日誌檔路徑（背景執行時建議指定）
)

# 若命令列未提供帳密，改從本機 config.ps1 讀取（config.ps1 不入庫）
if (-not $Username -or -not $Password) {
    $ConfigFile = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $ConfigFile) {
        . $ConfigFile
    }
}
if (-not $Username -or -not $Password) {
    Write-Host '請建立 config.ps1（複製 config.example.ps1 並填入帳密），或加 -Username/-Password 參數。'
    exit 1
}

$ErrorActionPreference = 'Continue'
$ProgressPreference  = 'SilentlyContinue'

# 連線測試網址：離線時會被重定向到認證頁
$TestUrls = @(
    'http://captive.apple.com',
    'http://www.msftconnecttest.com/connecttest.txt',
    'http://connect.rom.miui.com/generate_204'
)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

$script:CaptiveLoginUrl = $null

function Write-Log([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $line
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

# 確認 curl.exe 存在（Windows 10 1803+ 內建）
$curlPath = $null
try { $curlPath = (Get-Command curl.exe -ErrorAction Stop).Source } catch { }
if (-not $curlPath) {
    Write-Log '找不到 curl.exe（Windows 10 1803 以上已內建）。'
    exit 1
}

# 取得某網址「最終落地 URL」（重定向後）
function Get-FinalUrl([string]$url) {
    try {
        $out = (& $curlPath -s -L -o NUL -w '%{url_effective}' --max-time 8 --max-redirs 6 -A $UA $url 2>$null) | Out-String
        return $out.Trim()
    } catch { return '' }
}

# 偵測網路狀態：
#   'online'  → 已聯網（無重定向）
#   'captive' → 未認證，被重定向到認證頁（URL 存到 $script:CaptiveLoginUrl）
#   'offline' → 無網路（curl 全失敗，例如 WiFi 尚未連上／已關閉）
function Get-NetState {
    $script:CaptiveLoginUrl = $null
    foreach ($u in $TestUrls) {
        $final = Get-FinalUrl $u
        if ($final -eq '') { continue }
        if ($final -match 'login|/tpl/|srun') {
            $script:CaptiveLoginUrl = $final
            return 'captive'
        }
        return 'online'
    }
    return 'offline'
}

# 從 query string 取出指定參數
function Get-QueryParam([string]$query, [string]$name) {
    if (-not $query) { return '' }
    foreach ($pair in ($query.TrimStart('?') -split '&')) {
        if ($pair -match '^([^=]+)=(.*)$') {
            if ([uri]::UnescapeDataString($matches[1]) -eq $name) {
                return [uri]::UnescapeDataString($matches[2])
            }
        }
    }
    return ''
}

# 判斷登入回應是否成功（checkForm: code=0 成功 / code=1 失敗 / code=2 需驗證碼）
function Test-LoginSuccess([string]$resp) {
    if (-not $resp) { return $false }
    try {
        $j = $resp | ConvertFrom-Json
        $code = $j.code
        if ($code -eq 0 -or $code -eq '0') { return $true }
        if ($code -eq 2 -or $code -eq '2') {
            Write-Log '閘道要求驗證碼（code=2）：此帳戶/IP 被要求輸入驗證碼，請手動登入一次或稍後再試。'
            return $false
        }
        $errMsg = ''
        if ($j.authMsg)      { $errMsg = [string]$j.authMsg }
        elseif ($j.msg)      { $errMsg = [string]$j.msg }
        elseif ($j.info)     { $errMsg = [string]$j.info }
        elseif ($j.errorMsg) { $errMsg = [string]$j.errorMsg }
        if ($errMsg) { Write-Log ("閘道回覆：{0}" -f $errMsg) }
    } catch { }
    return $false
}

# 對閘道執行登入 POST（新版閘道有 CSRF 防護，需先取 token + session cookie）
function Invoke-Login([string]$base, [hashtable]$fields) {
    $parts = @()
    foreach ($k in $fields.Keys) {
        $parts += ("{0}={1}" -f $k, [uri]::EscapeDataString([string]$fields[$k]))
    }
    $body = $parts -join '&'
    $endpoint = "$base/api/account/login"
    $jar = Join-Path $env:TEMP 'whut_cookies.txt'

    # 1) 取得 CSRF token 與 session cookie（csrf.js：GET host_url + '/csrf-token'）
    $token = ''
    try {
        $csrfResp = (& $curlPath -s -c $jar "$base/api/csrf-token" --max-time 8 2>$null) | Out-String
        if ($csrfResp -match 'csrf_token"\s*:\s*"([^"]+)"') { $token = $matches[1] }
    } catch { }
    if (-not $token) {
        Write-Log '無法取得 CSRF token。'
        return ''
    }

    # 2) 帶 session cookie + X-CSRF-Token 標頭登入
    try {
        $raw = (& $curlPath -s -b $jar -X POST $endpoint `
            -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' `
            -H ("X-CSRF-Token: {0}" -f $token) `
            -H ("Referer: {0}" -f $base) `
            -A $UA --data $body --max-time 10 2>$null) | Out-String
        return $raw.Trim()
    } catch { return '' }
}

# 一次「偵測 → 登入」。回傳：online / offline / ok / fail
function Connect-Now {
    $state = Get-NetState
    if ($state -eq 'online')  { return 'online' }
    if ($state -eq 'offline') { return 'offline' }

    $loginUrl = $script:CaptiveLoginUrl
    Write-Log ("偵測到認證頁：{0}" -f $loginUrl)

    $u = $null
    try { $u = [uri]$loginUrl } catch { $u = $null }
    if (-not $u) { Write-Log '無法解析認證頁位址。'; return 'fail' }

    $base  = "{0}://{1}" -f $u.Scheme, $u.Authority
    $nasId = Get-QueryParam $u.Query 'nasId'
    Write-Log ("閘道 {0}  nasId={1}" -f $base, $nasId)

    # 與頁面 postData 完全一致：checkForm 只補 username/password/captcha，
    # 其餘欄位（switchip / userIpv4 / userMac）頁面本身留空。
    $fields = @{
        username  = $Username
        password  = $Password
        switchip  = ''
        nasId     = $nasId
        userIpv4  = ''
        userMac   = ''
        captcha   = ''
        captchaId = ''
    }
    $resp = Invoke-Login $base $fields
    if (Test-LoginSuccess $resp) {
        Write-Log '登入成功。'
        return 'ok'
    }
    Write-Log ("登入回應：{0}" -f $resp)
    return 'fail'
}

# ---------------- 主流程 ----------------
if ($Loop) {
    Write-Log ("常駐模式：已聯網時每 {0} 分鐘檢測一次；斷線／未連上時每 {1} 秒重試（Ctrl+C 結束）。" -f $IntervalMinutes, $RetrySeconds)
    while ($true) {
        $r = Connect-Now
        switch ($r) {
            'online'  { Write-Log '已在線。';        Start-Sleep -Seconds ($IntervalMinutes * 60) }
            'ok'      { Write-Log '已連上校園網。';  Start-Sleep -Seconds ($IntervalMinutes * 60) }
            'offline' { Write-Log '未連上校園網（WiFi 未連或已關閉），等待中…'; Start-Sleep -Seconds $RetrySeconds }
            'fail'    { Write-Log '登入失敗，稍後重試。'; Start-Sleep -Seconds $RetrySeconds }
        }
    }
} else {
    $r = Connect-Now
    switch ($r) {
        'online' {
            Write-Log '目前已在線。'
            exit 0
        }
        'offline' {
            Write-Log '未連上 WHUT-DORM（未偵測到校園網閘道）。'
            exit 1
        }
        'ok' {
            Start-Sleep -Seconds 3
            $still = Get-NetState
            if ($still -eq 'captive') { Write-Log '閘道回報成功，但重定向仍在，請稍候或檢查帳戶狀態。'; exit 0 }
            Write-Log '已成功連上校園網。'
            exit 0
        }
        default {
            Write-Log '登入失敗，請確認帳號、密碼與帳戶餘額/狀態。'
            exit 1
        }
    }
}
