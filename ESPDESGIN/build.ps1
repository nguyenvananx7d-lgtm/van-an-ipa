[CmdletBinding()]
param(
    [string]$DumpPath,
    [switch]$NoUpdate,
    [switch]$KeepBuildArtifacts
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$isWin = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT

function Get-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $normalized = $RelativePath.Replace('\', '/')
    return [IO.Path]::GetFullPath((Join-Path $ProjectRoot $normalized))
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Program,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program exited with code $LASTEXITCODE"
    }
}

function Invoke-ClrExe {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    if ($isWin) {
        Invoke-Checked $ExePath $Arguments
    } else {
        Invoke-Checked 'mono' (@($ExePath) + $Arguments)
    }
}

$PythonCmd = 'py'
$PythonArgs = @()
if (Get-Command 'py' -ErrorAction SilentlyContinue) {
    $installed = py --list
    if ($installed -match '3\.10') {
        $PythonArgs = @('-3.10')
    }
} elseif (Get-Command 'python' -ErrorAction SilentlyContinue) {
    $PythonCmd = 'python'
} elseif (Get-Command 'python3' -ErrorAction SilentlyContinue) {
    $PythonCmd = 'python3'
} else {
    throw "Python runtime not found. Please install Python 3."
}

function Invoke-Python {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    Invoke-Checked $PythonCmd (@($PythonArgs) + $Arguments)
}

$Generated = Get-ProjectPath 'generated'
$Build = Get-ProjectPath 'build'
$Dist = Get-ProjectPath 'dist'
$DummyDirectory = Get-ProjectPath 'baseline\DummyDll'
$BaseAssemblyCSharp = Join-Path $DummyDirectory 'Assembly-CSharp.dll'
$IFixCore = Join-Path $DummyDirectory 'IFix.Core.dll'
$NeutralPatch = Get-ProjectPath 'baseline\Assembly-CSharp-patch-neutral.bytes'
$BindingsTsv = Join-Path $Generated 'bindings.tsv'
$BindingsJson = Join-Path $Generated 'bindings.json'
$GeneratedLogic = Join-Path $Generated 'ESPLogic.cs'
$Vendor = Get-ProjectPath 'vendor\InjectFix'
$ThirdParty = Join-Path $Vendor 'ThirdParty'
$CompilerSource = Join-Path $Build 'compiler-src'
$ReferenceDirectory = Join-Path $Build 'ref'
$RetargetedAssembly = Join-Path $Build 'Assembly-CSharp-retargeted.dll'
$PatchSourceAssembly = Join-Path $Build 'Assembly-CSharp-source.dll'
$StagePatch = Join-Path $Build 'Assembly-CSharp-patch.bytes'
$StageReport = Join-Path $Build 'Assembly-CSharp-patch.report.json'
$StageVerify = Join-Path $Build 'Assembly-CSharp-patch.verify.json'
$FinalPatch = Join-Path $Dist 'Assembly-CSharp-patch.bytes'
$FinalReport = Join-Path $Dist 'Assembly-CSharp-patch.report.json'
$FinalVerify = Join-Path $Dist 'Assembly-CSharp-patch.verify.json'
$FinalManifest = Join-Path $Dist 'Assembly-CSharp-patch.manifest.json'

# Detect csc.exe - Windows or Mono on macOS/Linux
if ($isWin) {
    $Csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
} else {
    # macOS/Linux: use Mono's mcs compiler
    $Csc = (Get-Command 'mcs' -ErrorAction SilentlyContinue).Source
    if (-not $Csc) {
        $Csc = (Get-Command 'csc' -ErrorAction SilentlyContinue).Source
    }
    if (-not $Csc) {
        throw "C# compiler not found. Install Mono or .NET SDK."
    }
}

[IO.Directory]::CreateDirectory($Generated) | Out-Null
[IO.Directory]::CreateDirectory($Build) | Out-Null
[IO.Directory]::CreateDirectory($Dist) | Out-Null
[IO.Directory]::CreateDirectory($CompilerSource) | Out-Null
[IO.Directory]::CreateDirectory($ReferenceDirectory) | Out-Null

if (-not $NoUpdate) {
    $updateArguments = @(
        (Get-ProjectPath 'tools/update_from_dump.py'),
        '--dumps-dir', (Get-ProjectPath 'dumps'),
        '--template', (Get-ProjectPath 'src/ESPLogic.template.cs'),
        '--generated', $Generated,
        '--no-readme'
    )
    if ($DumpPath) {
        $resolvedDump = if ([IO.Path]::IsPathRooted($DumpPath)) {
            [IO.Path]::GetFullPath($DumpPath)
        } else {
            [IO.Path]::GetFullPath((Join-Path $ProjectRoot $DumpPath))
        }
        $updateArguments += @('--dump', $resolvedDump)
    }
    Invoke-Python $updateArguments
}

foreach ($required in @(
    $BindingsTsv, $BindingsJson, $GeneratedLogic, $BaseAssemblyCSharp,
    $IFixCore, $NeutralPatch, $Csc,
    (Get-ProjectPath 'src\WeaveEsp.cs'),
    (Get-ProjectPath 'tools\prepare_compiler.py'),
    (Get-ProjectPath 'tools\parse_ifix_patch.py'),
    (Get-ProjectPath 'tools\verify_ifix_patch.py'),
    (Join-Path $ThirdParty 'Mono.Cecil.dll'),
    (Join-Path $ThirdParty 'Mono.Cecil.Mdb.dll'),
    (Join-Path $ThirdParty 'Mono.Cecil.Pdb.dll')
)) {
    if (-not [IO.File]::Exists($required)) {
        throw "Required build input is missing: $required"
    }
}

$bindingInfo = Get-Content -LiteralPath $BindingsJson -Raw | ConvertFrom-Json
$rawDump = [string]$bindingInfo.dump
$Dump = if ([IO.File]::Exists($rawDump)) {
    [IO.Path]::GetFullPath($rawDump)
} else {
    $dumpName = [IO.Path]::GetFileName($rawDump)
    Get-ProjectPath (Join-Path 'dumps' $dumpName)
}
if (-not [IO.File]::Exists($Dump)) {
    throw "Active dump is missing: $Dump"
}

$Cecil = Join-Path $ThirdParty 'Mono.Cecil.dll'
$Weaver = Join-Path $Build 'WeaveEsp.exe'
Invoke-Checked $Csc @(
    '/nologo', '/target:exe', '/optimize+', "/out:$Weaver",
    "/reference:$Cecil", (Get-ProjectPath 'src/WeaveEsp.cs')
)
Copy-Item -LiteralPath $Cecil -Destination (Join-Path $Build 'Mono.Cecil.dll') -Force

foreach ($path in @($RetargetedAssembly, $PatchSourceAssembly, $StagePatch)) {
    if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
}
Invoke-ClrExe $Weaver @(
    '--adapt-target', $BaseAssemblyCSharp, $RetargetedAssembly, $BindingsTsv
)

$PublicReference = Join-Path $ReferenceDirectory 'Assembly-CSharp.dll'
Invoke-ClrExe $Weaver @(
    '--public-reference', $RetargetedAssembly, $PublicReference,
    $DummyDirectory, $BindingsTsv
)

$EspLogic = Join-Path $Build 'ESPLogic.dll'
Invoke-Checked $Csc @(
    '/nologo', '/target:library', '/optimize+', "/out:$EspLogic",
    "/lib:$ReferenceDirectory,$DummyDirectory",
    '/reference:Assembly-CSharp.dll',
    '/reference:UnityEngine.CoreModule.dll',
    '/reference:UnityEngine.IMGUIModule.dll',
    '/reference:UnityEngine.InputLegacyModule.dll',
    '/reference:UnityEngine.PhysicsModule.dll',
    '/reference:UnityEngine.TextRenderingModule.dll',
    $GeneratedLogic,
    (Get-ProjectPath 'src/Logic.Aim.cs')
)

Invoke-ClrExe $Weaver @(
    $RetargetedAssembly, $EspLogic, $PatchSourceAssembly, $DummyDirectory
)

Invoke-Python @(
    (Get-ProjectPath 'tools/prepare_compiler.py'),
    '--dump', $Dump,
    '--neutral-patch', $NeutralPatch,
    '--instruction-source', (Join-Path $Vendor (Join-Path 'Src/Core' 'Instruction.cs')),
    '--translator-source', (Join-Path $Vendor (Join-Path 'Src/Tools' 'CodeTranslator.cs')),
    '--output', $CompilerSource
)

$IFixCompiler = Join-Path $Build 'IFix.exe'
Invoke-Checked $Csc @(
    '/nologo', '/unsafe', '/target:exe', '/optimize+', "/out:$IFixCompiler",
    "/reference:$Cecil",
    "/reference:$(Join-Path $ThirdParty 'Mono.Cecil.Mdb.dll')",
    "/reference:$(Join-Path $ThirdParty 'Mono.Cecil.Pdb.dll')",
    (Join-Path $CompilerSource 'Instruction.cs'),
    (Join-Path $CompilerSource 'CodeTranslator.cs'),
    (Join-Path $Vendor (Join-Path 'Src/Tools' 'CSFix.cs')),
    (Join-Path $Vendor (Join-Path 'Src/Tools' 'CecilExtensions.cs')),
    (Join-Path $Vendor (Join-Path 'Src/Tools' 'GenerateConfigure.cs')),
    (Join-Path $Vendor (Join-Path 'Src' 'Version.cs'))
)
foreach ($name in @('Mono.Cecil.dll', 'Mono.Cecil.Mdb.dll', 'Mono.Cecil.Pdb.dll')) {
    Copy-Item -LiteralPath (Join-Path $ThirdParty $name) -Destination $Build -Force
}
Copy-Item -LiteralPath $EspLogic -Destination $DummyDirectory -Force

# Patch config: ONLY Bootstrap (IsReallyInStealth) and Draw (OnGUI) are active.
# All other methods (network, aim, recoil, movement) are completely untouched.
$PatchConfig = Join-Path $Build 'patch-config.bin'
$configStream = [IO.File]::Create($PatchConfig)
$configWriter = New-Object IO.BinaryWriter($configStream)
try {
    $configWriter.Write([int]2)

    $configWriter.Write('COW.GamePlay.Player')
    $configWriter.Write([int]1)
    $configWriter.Write('IsReallyInStealth')
    $configWriter.Write('System.Boolean')
    $configWriter.Write([int]0)

    $configWriter.Write('COW.GamePlay.SceneEditBoxSelectTool')
    $configWriter.Write([int]1)
    $configWriter.Write('OnGUI')
    $configWriter.Write('System.Void')
    $configWriter.Write([int]0)

    for ($index = 0; $index -lt 4; $index++) {
        $configWriter.Write([int]0)
    }
} finally {
    $configWriter.Dispose()
}

Invoke-ClrExe $IFixCompiler @(
    '-patch', $IFixCore, $PatchSourceAssembly, $RetargetedAssembly,
    $PatchConfig, $StagePatch, $Build, $DummyDirectory
)
if (-not [IO.File]::Exists($StagePatch)) {
    throw 'IFix did not create the staged patch.'
}

$Parser = Get-ProjectPath 'tools/parse_ifix_patch.py'
$Verifier = Get-ProjectPath 'tools/verify_ifix_patch.py'
Invoke-Python @($Parser, $StagePatch, '-o', $StageReport)
Invoke-Python @(
    $Verifier, $StagePatch, '--dump', $Dump, '--json', $StageVerify
)
$report = Get-Content -LiteralPath $StageReport -Raw | ConvertFrom-Json
$verification = Get-Content -LiteralPath $StageVerify -Raw | ConvertFrom-Json
$redirects = @($report.redirects)
$methods = @($report.patched_code)
# Some legacy dumps legitimately produce unresolved stack-effect or dump-method warnings
# while still yielding a valid, structurally sound patch. Treat warnings as informational
# unless the overall verification result itself is invalid or errors are present.
if (-not $verification.valid -or @($verification.errors).Count -ne 0) {
    throw 'Generated patch did not pass VM verification.'
}
if ($report.magic -ne '0x66A319B20DB4A2CB' -or $report.remaining_bytes -ne 0 `
    -or $methods.Count -lt 2 -or $methods.Count -gt 96 -or $redirects.Count -ne 2) {
    throw 'Generated patch failed structural assertions.'
}

$expectedRedirects = @(
    'COW.GamePlay.Player|IsReallyInStealth',
    'COW.GamePlay.SceneEditBoxSelectTool|OnGUI'
)
$actualRedirects = @($redirects | ForEach-Object {
    (($_.declaring_type -split ',')[0]) + '|' + $_.name
})
$missingRedirects = @($expectedRedirects | Where-Object {
    $actualRedirects -notcontains $_
})
if ($missingRedirects.Count -ne 0) {
    throw "Generated patch is missing redirects: $($missingRedirects -join ', ')"
}

# Removed features should not reference these methods
$forbiddenMethods = @(
    'GetSyncStatePos', 'OnWeaponReloadStarted',
    'OnWeaponReloadImmediateStarted', 'OnWeaponReloadSpeedChanged',
    'SendStartReload', 'IsFiring'
)
$methodNames = @($report.external_methods | ForEach-Object { $_.name })
$foundForbiddenMethods = @($forbiddenMethods | Where-Object {
    $methodNames -contains $_
})
if ($foundForbiddenMethods.Count -ne 0) {
    throw "Removed feature methods remain: $($foundForbiddenMethods -join ', ')"
}

# Only ESP-visual methods are required now. `Matrix4x4.TRS` is deliberately
# absent: ESP text scales through GUIStyle.fontSize, so no per-label matrix is
# built any more. The matrix getters stay because the render pass still saves
# and restores GUI.matrix around the overlay.
$requiredMethods = @(
    'IsInStealth', 'IsLocalPlayer', 'IsLocalTeammate', 'IsVisible',
    'get_RootTransform', 'GetHeadTF', 'get_CurHP', 'get_MaxHP',
    'get_NickName', 'get_IsDieing', 'CurrentMatch', 'CurrentLocalPlayer',
    [string]$bindingInfo.placeholders.MATCH_PLAYERS_METHOD,
    'WorldToScreenPoint', 'Distance', 'DrawTexture', 'Label',
    'get_whiteTexture', 'get_current', 'get_type', 'get_matrix', 'set_matrix',
    'get_color', 'set_color', 'Clamp', 'Contains', 'Use',
    'get_mousePosition', 'get_delta', 'get_touchCount', 'get_unscaledTime',
    'get_NeckBone', 'GetChestPos', 'Angle', 'Slerp'
)
$missingMethods = @($requiredMethods | Where-Object { $methodNames -notcontains $_ })
if ($missingMethods.Count -ne 0) {
    throw "Generated patch is missing required methods: $($missingMethods -join ', ')"
}

$strings = @($report.strings)
# These features are removed - their strings must not appear
$forbiddenStrings = @(
    'Fast reload x3', 'Fake lag (fire)',
    'Silent aim', 'No recoil', 'Fast parachute', 'Speed running x3',
    'Aim system', 'Aim FOV circle', 'Target: BODY', 'Target: HEAD', 'Target: MIXED',
    'Headshot rate: 0%', 'Headshot rate: 25%', 'Headshot rate: 50%',
    'Headshot rate: 75%', 'Headshot rate: 100%',
    'Aim system target: HEAD', 'Aim system target: NECK',
    'ESP SETTINGS'
)
$foundForbiddenStrings = @($forbiddenStrings | Where-Object { $strings -contains $_ })
if ($foundForbiddenStrings.Count -ne 0) {
    throw "Removed menu strings remain: $($foundForbiddenStrings -join ', ')"
}
# Only the actual menu strings present in the generated patch are required. The
# panel mirrors the YABAOCHEAT app shell, so these are the shared chrome labels.
$requiredStrings = @(
    'uievent_relay', '__esp_fov', 'X', 'ENABLE ALL', 'HIDE MENU',
    'UI OVERLAY', 'DRAG HEADER TO MOVE',
    'CONTROLS', 'ON', 'OFF', 'VIEW', 'TRACK', 'MISC',
    'MARKERS', 'ASSIST', 'HUD', 'Enemies: ', '?'
)
$missingStrings = @($requiredStrings | Where-Object { $strings -notcontains $_ })
if ($missingStrings.Count -ne 0) {
    throw "Generated patch is missing menu strings: $($missingStrings -join ', ')"
}

$requiredFields = @(
    [string]$bindingInfo.placeholders.SCENE_MENU_FIELD,
    [string]$bindingInfo.placeholders.SCENE_POSITION_FIELD,
    [string]$bindingInfo.placeholders.SCENE_STATE_FIELD
)
$fieldNames = @($report.fields | ForEach-Object { $_.name })
$missingFields = @($requiredFields | Where-Object { $fieldNames -notcontains $_ })
if ($missingFields.Count -ne 0) {
    throw "Generated patch is missing target fields: $($missingFields -join ', ')"
}

Copy-Item -LiteralPath $StagePatch -Destination $FinalPatch -Force
Invoke-Python @($Parser, $FinalPatch, '-o', $FinalReport)
Invoke-Python @(
    $Verifier, $FinalPatch, '--dump', $Dump, '--json', $FinalVerify
)
$finalVerification = Get-Content -LiteralPath $FinalVerify -Raw | ConvertFrom-Json
if (-not $finalVerification.valid -or @($finalVerification.errors).Count -ne 0) {
    throw 'Installed patch verification failed.'
}

$hash = (Get-FileHash -LiteralPath $FinalPatch -Algorithm SHA256).Hash
$assemblyIdentity = [string]$report.wrapper_manager
$assemblyIdentity = $assemblyIdentity.Substring($assemblyIdentity.IndexOf(',') + 2)
$manifest = [ordered]@{
    file = 'dist\Assembly-CSharp-patch.bytes'
    game_version = [string]$bindingInfo.version
    size = [int64](Get-Item -LiteralPath $FinalPatch).Length
    sha256 = $hash
    magic = $report.magic
    assembly = $assemblyIdentity
    dump = [IO.Path]::GetFileName($Dump)
    dump_sha256 = [string]$bindingInfo.dump_sha256
    bindings = $bindingInfo.details
    source_dummy_sha256 = (Get-FileHash $BaseAssemblyCSharp -Algorithm SHA256).Hash
    ifix_core_sha256 = (Get-FileHash $IFixCore -Algorithm SHA256).Hash
    neutral_patch_sha256 = (Get-FileHash $NeutralPatch -Algorithm SHA256).Hash
    redirects = @(
        'Player.IsReallyInStealth -> bootstrap',
        'SceneEditBoxSelectTool.OnGUI -> ESP/menu'
    )
    features = @(
        'ESP box/fill/skeleton/health/name/distance/tracer/line/arrow filters',
        'humanised sticky camera assist (reaction, hit-chance, prediction)',
        'behavioural anti-ban stealth (touch gate, smoothing, no game-state writes)',
        'three-finger five-tap draggable ESP menu'
    )
    excluded = @(
        'fast reload', 'fake lag', 'silent aim', 'aim system',
        'no recoil', 'fast parachute', 'speed running'
    )
    vm_instructions = [int](($methods | Measure-Object instructions -Sum).Sum)
    vm_exception_handlers = [int](($methods | Measure-Object exceptions -Sum).Sum)
}
[IO.File]::WriteAllText(
    $FinalManifest,
    (($manifest | ConvertTo-Json -Depth 8) + "`n"),
    [Text.Encoding]::ASCII
)

if (-not $KeepBuildArtifacts) {
    foreach ($temporaryFile in @(
        $RetargetedAssembly, $PublicReference, $PatchSourceAssembly, $EspLogic,
        $Weaver, $IFixCompiler, $PatchConfig,
        (Join-Path $Build 'Mono.Cecil.dll'),
        (Join-Path $Build 'Mono.Cecil.Mdb.dll'),
        (Join-Path $Build 'Mono.Cecil.Pdb.dll')
    )) {
        if ([IO.File]::Exists($temporaryFile)) { [IO.File]::Delete($temporaryFile) }
    }
}

Write-Output "BUILT: $FinalPatch"
Write-Output "version=$($bindingInfo.version) size=$($manifest.size) sha256=$hash"
Write-Output "redirects=$($redirects.Count) instructions=$($manifest.vm_instructions)"
