[CmdletBinding()]
param(
    [string]$DumpPath,
    [switch]$KeepBuildArtifacts
)

$arguments = @{}
if ($DumpPath) { $arguments.DumpPath = $DumpPath }
if ($KeepBuildArtifacts) { $arguments.KeepBuildArtifacts = $true }

& (Join-Path $PSScriptRoot 'build.ps1') @arguments
if (-not $?) { exit 1 }
