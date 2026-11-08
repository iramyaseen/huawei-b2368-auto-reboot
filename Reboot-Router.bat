@echo off
cd /d "%~dp0"
echo Rebooting Huawei B2368-66 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0huawei-b2368-reboot.ps1" -Auto -WaitOnline
echo.
pause
