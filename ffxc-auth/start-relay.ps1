# One-click relay starter for the no-VPS setup. Runs both servers detached
# from the shell so closing the terminal does not kill them. Logs land in
# auth-run.log / proxy-run.log next to this script.
$ErrorActionPreference = 'Stop'

$env:PATH = "C:\nodeportable\node-v26.12.1-win-x64;" + $env:PATH
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

$env:RELAY_PATCH_HOST     = "192.168.0.106"
$env:RELAY_PUBLIC_HOST    = "192.168.0.106"
$env:RELAY_PATCH_FILE     = "C:\Users\Windows\Downloads\van-an-ipa-clone\YABAOCHEAT\Resources\Assembly-CSharp-patch.bytes"
$env:RELAY_PATCH_PATH     = "/cdn/patch/Assembly-CSharp-patch.bytes"

# Kill any previous instances so ports are free.
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force

Start-Process -FilePath "node" -ArgumentList "--env-file=.env","dist/src/server.js" `
  -WorkingDirectory $here -WindowStyle Hidden `
  -RedirectStandardOutput "$here\auth-run.log" -RedirectStandardError "$here\auth-run.err.log"

Start-Process -FilePath "node" -ArgumentList "--env-file=.env","dist/src/proxy/server.js" `
  -WorkingDirectory $here -WindowStyle Hidden `
  -RedirectStandardOutput "$here\proxy-run.log" -RedirectStandardError "$here\proxy-run.err.log"

Start-Sleep -Seconds 4
Write-Host "auth  : http://192.168.0.106:8787"
Write-Host "admin : http://192.168.0.106:8080"
Write-Host "proxy : 192.168.0.106:1299"
