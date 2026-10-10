@echo off
setlocal
echo Stopping ffxc-auth (watchdog + node)...
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and ($_.CommandLine -like '*run-forever.cmd*' -or $_.CommandLine -like '*dist/src/server.js*') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo Done.
