@echo off
rem 點兩下即可連接校園網；亦可傳入參數，例如： connect.bat -Loop
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0whut-auto-connect.ps1" %*
pause
