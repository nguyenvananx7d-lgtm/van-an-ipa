@echo off
setlocal
cd /d "%~dp0"
if not exist "logs" mkdir "logs"

if exist "logs\server.log" for %%A in ("logs\server.log") do if %%~zA GTR 10485760 move /y "logs\server.log" "logs\server.old.log" >nul

:loop
echo [%date% %time%] starting ffxc-auth >> "logs\server.log"
"C:\Program Files\nodejs\node.exe" --env-file=.env dist/src/server.js >> "logs\server.log" 2>&1
echo [%date% %time%] ffxc-auth exited (code %errorlevel%), restart in 5s >> "logs\server.log"
ping -n 6 127.0.0.1 >nul
goto loop
