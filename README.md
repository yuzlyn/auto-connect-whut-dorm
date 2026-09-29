# auto-connect-whut-dorm

武漢理工大學（WHUT）宿舍網／校園網自動登入腳本，取代每次手動在認證頁輸入帳密或手動 JS 注入。

- 認證系統：**深瀾 Web 認證**（新版，帶 CSRF 防護）
- 適用網路：`WHUT-DORM`（宿舍網）、`WHUT-WLAN`（無線）
- 平台：Windows

> ⚠️ 請勿把 `config.ps1` 或含帳密的檔案上傳到 GitHub。

## 方案對照

| 方案 | 檔案 | 需要開瀏覽器？ | 說明 |
|------|------|--------------|------|
| **A. PowerShell 全自動** | `whut-auto-connect.ps1` | 不需要 | 背景直接 POST 登入，可開機常駐、斷線自動重連 |
| **B. 油猴腳本（Tampermonkey）** | `WHUT-DORM-auto-login.user.js` | 需要（自動觸發） | 直接呼叫認證頁的 `checkForm()`，最穩 |

---

## 方案 A：PowerShell（免瀏覽器，推薦）

### 1. 設定帳密

```powershell
Copy-Item config.example.ps1 config.ps1
```

編輯 `config.ps1`，填入你的上網帳號與密碼：

```powershell
$Username = '你的學號'
$Password = '你的密碼'
```

> `config.ps1` 已加入 `.gitignore`，不會被上傳。

### 2. 手動連接一次

先連上 `WHUT-DORM` Wi-Fi（尚未登入沒關係），然後：

```powershell
powershell -ExecutionPolicy Bypass -File .\whut-auto-connect.ps1
```

或直接點兩下 `connect.bat`。

### 3. 開機自動連接＋常駐檢測（一次性設定）

以「系統管理員」開 PowerShell，執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-task.ps1
```

效果：

- 每次登入 Windows 就於**背景**啟動；
- 已在線 → **每 60 分鐘檢測一次**；
- 斷線／未連上 → **每 60 秒自動重連**；
- 一直連著，除非你手動關網路／登出／停用。

自訂間隔（手動跑常駐時）：

```powershell
powershell -ExecutionPolicy Bypass -File .\whut-auto-connect.ps1 -Loop -IntervalMinutes 30 -RetrySeconds 120
```

移除排程：

```powershell
Unregister-ScheduledTask -TaskName 'WHUT-AutoConnect' -Confirm:$false
```

---

## 方案 B：Tampermonkey 油猴腳本

1. 安裝 [Tampermonkey](https://www.tampermonkey.net/) 擴充套件（Chrome / Edge）。
2. 新增腳本，貼上 `WHUT-DORM-auto-login.user.js` 內容。
3. 把腳本開頭的 `USERNAME` / `PASSWORD` 改成你的帳密。
4. 之後瀏覽器一開到認證頁（連上 WHUT-DORM 後開啟任意 `http://` 網址，或系統跳出登入頁），就會自動填入帳密並送出。

> 若系統跳出 Windows 的「登入」提示用的是內建瀏覽器（沒有 Tampermonkey），改用手動開 Chrome/Edge 造訪任意 `http://` 網站即可觸發。

---

## 運作原理（已驗證）

未認證時，出口閘道把 `http://captive.apple.com` 等請求重定向到認證頁：

```
http://<閘道>/tpl/whut/login.html?acip=…&acname=…&ip=…&nasId=52&userip=…&wlanacname=
```

登入流程（新版閘道有 CSRF 防護）：

1. `GET http://<閘道>/api/csrf-token` → 取得 `csrf_token` 並儲存 `yudear` session cookie；
2. `POST http://<閘道>/api/account/login`
   - 標頭：`X-CSRF-Token: <csrf_token>`
   - Body：`username`、`password`、`nasId`、`switchip`、`userIpv4`、`userMac`、`captcha`、`captchaId`（僅前三者有值，其餘留空）
   - 回傳：`code=0` 成功、`code=1` 失敗、`code=2` 需驗證碼

閘道 IP 可能變動（曾見 `172.30.16.33`、`172.30.21.100`），腳本會由重定向自動發現，不寫死。

## 檔案說明

| 檔案 | 用途 |
|------|------|
| `whut-auto-connect.ps1` | 主腳本：偵測＋登入，支援 `-Loop` 常駐 |
| `config.example.ps1` | 帳密範本（複製為 `config.ps1` 使用） |
| `setup-task.ps1` | 建立「開機自動連接」工作排程器 |
| `connect.bat` | 點兩下連接一次 |
| `WHUT-DORM-auto-login.user.js` | Tampermonkey 油猴腳本 |
