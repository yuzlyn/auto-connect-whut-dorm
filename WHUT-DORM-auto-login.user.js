// ==UserScript==
// @name         WHUT-DORM 校園網自動登入
// @namespace    https://whut.edu.cn/
// @version      1.0.0
// @description  自動填入帳號密碼並呼叫 checkForm() 提交，等同你原本手動 JS 注入，但全自動。適用武漢理工深瀾 Web 認證頁。
// @match        http://*/*
// @match        https://*/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
    'use strict';

    // ===== 設定：改成你的帳號密碼 =====
    const USERNAME = 'YOUR_USERNAME';   // ← 改成你的學號
    const PASSWORD = 'YOUR_PASSWORD';   // ← 改成你的密碼
    // ==================================

    // 是否已觸發過（避免頁面重載後無限重送）
    let submitted = false;

    function tryLogin() {
        const uname = document.querySelector('#username');
        const pswd  = document.querySelector('#password');
        if (!uname || !pswd) return false;            // 不是登入頁
        if (typeof checkForm !== 'function') return false;

        uname.value = USERNAME;
        pswd.value  = PASSWORD;

        try {
            checkForm();                               // 等同你手動點「連接」
            submitted = true;
            console.log('[WHUT-DORM] 已觸發自動登入');
            return true;
        } catch (e) {
            console.error('[WHUT-DORM] 登入觸發失敗：', e);
            return false;
        }
    }

    // 欄位可能延遲載入，輪詢數次（約 20 秒）
    let tries = 0;
    const timer = setInterval(function () {
        tries++;
        if (submitted) { clearInterval(timer); return; }
        if (tryLogin() || tries > 40) {
            clearInterval(timer);
        }
    }, 500);
})();
