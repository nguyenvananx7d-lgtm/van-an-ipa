@echo off
setlocal
cd /d "%~dp0"
if not exist "logs" mkdir "logs"

:loop
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
  echo [%date% %time%] another ffxc-auth instance already serves 8787, exit >> "logs\watchdog.log"
  exit /b 0
)
if exist "logs\server.log" for %%A in ("logs\server.log") do if %%~zA GTR 10485760 move /y "logs\server.log" "logs\server.old.log" >nul 2>nul
echo [%date% %time%] starting ffxc-auth >> "logs\watchdog.log"
"C:\Program Files\nodejs\node.exe" --env-file=.env dist/src/server.js >> "logs\server.log" 2>&1
echo [%date% %time%] ffxc-auth exited (code %errorlevel%), restart in 5s >> "logs\watchdog.log"
ping -n 6 127.0.0.1 >nul
goto loop
