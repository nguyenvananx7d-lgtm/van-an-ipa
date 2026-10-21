$ErrorActionPreference = 'Stop'
$py = if (Get-Command 'py' -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
$pyArgs = @()
if ($py -eq 'py') {
    $installed = py --list
    if ($installed -match '3\.10') { $pyArgs = @('-3.10') }
}
& $py @pyArgs -m unittest discover -s (Join-Path $PSScriptRoot 'tools') -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
