<#
Reassembles the real IFix patch from the app's `DUMP: PATCHB64 ...` log lines.

The container dump emits the patch as base64 in 1000-char chunks:

    DUMP: PATCHB64 Documents/Assembly-CSharp-patch.bytes bytes=76348 sha256=<hex> chunks=102
    DUMP: PATCHB64 1/102 <base64...>
    DUMP: PATCHB64 2/102 <base64...>
    ...

This script collects the indexed parts, concatenates them in order,
base64-decodes, checks length and SHA-256 against the header line, and writes
the blob. Feed it the raw log — any surrounding text is ignored. It is the
same artifact the app also drops at Documents/captured-* for a Files/Filza
pull, but the log alone is enough.

Usage:
    ./tools/Reassemble-Patch.ps1 -Log patch-log.txt
    ./tools/Reassemble-Patch.ps1 -Log patch-log.txt -Out YABAOCHEAT/Resources/Assembly-CSharp-patch.bytes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Log,
    [string]$Out = 'Assembly-CSharp-patch.bytes'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$text = Get-Content -Raw -LiteralPath $Log

$header = [regex]::Match(
    $text,
    'PATCHB64\s+(\S+)\s+bytes=(\d+)\s+sha256=([0-9a-fA-F]{64})\s+chunks=(\d+)'
)
if (-not $header.Success) {
    throw "no 'PATCHB64 <label> bytes=<n> sha256=<hex> chunks=<k>' header found in $Log"
}

$label  = $header.Groups[1].Value
$bytes  = [int]$header.Groups[2].Value
$sha    = $header.Groups[3].Value.ToLowerInvariant()
$chunks = [int]$header.Groups[4].Value

$parts = @{}
foreach ($m in [regex]::Matches($text, 'PATCHB64\s+(\d+)/(\d+)\s+([A-Za-z0-9+/=]+)')) {
    $parts[[int]$m.Groups[1].Value] = $m.Groups[3].Value
}
if ($parts.Count -ne $chunks) {
    throw "expected $chunks chunks, found $($parts.Count)"
}

$sb = New-Object System.Text.StringBuilder
for ($i = 1; $i -le $chunks; $i++) {
    if (-not $parts.ContainsKey($i)) { throw "missing chunk $i/$chunks" }
    [void]$sb.Append($parts[$i])
}

$data = [Convert]::FromBase64String($sb.ToString())
if ($data.Length -ne $bytes) {
    throw "length mismatch: header says $bytes, decoded $($data.Length)"
}

$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hash   = $sha256.ComputeHash([byte[]]$data)
$sha256.Dispose()
$hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
if ($hex -ne $sha) {
    throw "sha256 mismatch: header says $sha, decoded $hex"
}

$outPath = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$outPath = [System.IO.Path]::GetFullPath($outPath)
[System.IO.File]::WriteAllBytes($outPath, $data)

Write-Host "label   : $label"
Write-Host "bytes   : $($data.Length)"
Write-Host "sha256  : $hex"
Write-Host "written : $outPath"
