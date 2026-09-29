# ============================================================
#  建立「開機自動連接校園網」工作排程器（一次性設定）
#  ============================================================
#  用法（以系統管理員身分執行）：
#    powershell -ExecutionPolicy Bypass -File .\setup-task.ps1
#
#  效果：每次登入 Windows 時，於背景啟動 whut-auto-connect.ps1 -Loop，
#        已聯網時每 60 分鐘檢測一次、斷線／未連上時每 60 秒重試，
#        直到你登出或手動停用才停止。
#
#  移除：
#    Unregister-ScheduledTask -TaskName 'WHUT-AutoConnect' -Confirm:$false
# ============================================================

$TaskName = 'WHUT-AutoConnect'
$Script   = Join-Path $PSScriptRoot 'whut-auto-connect.ps1'
$LogFile  = Join-Path $PSScriptRoot 'whut-auto-connect.log'

# 需系統管理員
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '請以「系統管理員」身分執行此腳本（在開始功能表搜尋 PowerShell → 右鍵 → 以系統管理員身分執行）。' -ForegroundColor Red
    exit 1
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`" -Loop -IntervalMinutes 60 -RetrySeconds 60 -LogFile `"$LogFile`""

# 登入時觸發（WiFi 通常在登入後自動連上）
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -User $currentUser -Description 'WHUT-DORM 開機自動登入並常駐，每小時檢測、斷線自動重連' -Force | Out-Null

Write-Host "已建立排程工作「$TaskName」。" -ForegroundColor Green
Write-Host '它會在每次登入時於背景啟動，已聯網每 60 分鐘檢測一次、斷線每 60 秒自動重連。'
Write-Host "日誌檔：$LogFile"
Write-Host "想立刻測試可執行：Start-ScheduledTask -TaskName '$TaskName'"
