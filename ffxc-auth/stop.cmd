@echo off
setlocal
echo Stopping ffxc-auth (watchdog + node)...
rem Only touch: node.exe running the server, and the cmd.exe watchdog.
rem (Matching by process name keeps this from killing unrelated shells.)
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and (($_.Name -eq 'node.exe' -and $_.CommandLine -like '*dist/src/server.js*') -or ($_.Name -eq 'cmd.exe' -and $_.CommandLine -like '*run-forever.cmd*')) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
echo Done.
