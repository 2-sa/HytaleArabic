param(
    [string]$GameRoot=(Join-Path $env:APPDATA 'Hytale'),
    [string]$PackageRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'package')
)
. "$PSScriptRoot\Common.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$app=Split-Path $PSScriptRoot -Parent
$baseline=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'baseline-0.7.0.json')) | ConvertFrom-Json
$progressTotal=10+($baseline.Files.Count*3)+@($baseline.Files|Where-Object {$null -ne $_.BeforeHash}).Count
$sharedRel='install\release\package\game\latest\Client\Data\Shared'
$shared=Join-Path $root $sharedRel
$english=Join-Path $shared 'Language\en-US\client.lang'
$assets=Join-Path $root 'install\release\package\game\latest\Assets.zip'
Assert-Closed
$statePath=Join-Path $root 'UserData\HytaleArabicManager\state.json'
if(Test-Path -LiteralPath $statePath){
    $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
    if($state.Status -ne 'removed'){throw 'Existing localization must be restored before preparing a new package.'}
}
if((File-Hash $english) -ne $baseline.EnglishClientHash -or (File-Hash $assets) -ne $baseline.AssetsHash){
    throw 'Game version changed; Hytale 0.7.0 source cannot be applied.'
}
foreach($entry in $baseline.Files){
    $target=Assert-Contained $root $entry.Relative
    if((File-Hash $target) -ne $entry.BeforeHash){throw "Original game file differs: $($entry.Relative)"}
}
if(Test-Path -LiteralPath $package){throw 'Package directory already exists; inspect it before rebuilding.'}

$stage=Join-Path $app ('build-local-'+[guid]::NewGuid().ToString('N'))
$refs=Join-Path $stage 'references'
$fonts=Join-Path $stage 'fonts'
$loading=Join-Path $stage 'loading'
$world=Join-Path $stage 'world'
$prepared=Join-Path $stage 'package'
[void][IO.Directory]::CreateDirectory($stage)
try{
    Write-Output "PROGRESS|install|0|$progressTotal|version"
    & (Join-Path $PSScriptRoot 'SnapshotGameReferences.ps1') -GameDirectory (Join-Path $root 'install\release\package\game\latest') -OutputDirectory $refs
    if(!$?){throw 'Reference snapshot failed.'}
    Write-Output "PROGRESS|install|1|$progressTotal|fonts"
    $fontStep=1
    foreach($font in @('Lexend-Bold','NunitoSans-Medium','NunitoSans-ExtraBold','NotoSans-Bold','NotoMono-Regular')){
        & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'tests\BuildInterface.ps1') -GameRoot $root -FontName $font -FontDirectory (Join-Path $shared 'UI\Fonts') -OutputDirectory $fonts
        if($LASTEXITCODE -ne 0){throw "Arabic font generation failed: $font"}
        $fontStep++
        Write-Output "PROGRESS|install|$fontStep|$progressTotal|fonts"
    }
    Write-Output "PROGRESS|install|7|$progressTotal|world"
    & "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'tests\BuildWorld.ps1') -GameRoot $root -FontDirectory $fonts -ReferenceDirectory $refs -OutputDirectory $world
    if($LASTEXITCODE -ne 0){throw 'World package generation failed.'}
    Write-Output "PROGRESS|install|8|$progressTotal|loading"
    & (Join-Path $app 'tests\BuildLoading.ps1') -GameRoot $root -OriginalShared $shared -InterfaceDirectory $fonts -OutputDirectory $loading
    if(!$?){throw 'Loading interface generation failed.'}
    Write-Output "PROGRESS|install|9|$progressTotal|verify"
    & (Join-Path $PSScriptRoot 'PrepareLocalPackage.ps1') -GameRoot $root -OriginalRoot $root -ReferenceDirectory $refs -InterfaceDirectory $fonts -LoadingDirectory $loading -WorldZip (Join-Path $world 'OriginalArabic-HytaleArabic.zip') -OutputDirectory $prepared
    if(!$?){throw 'Local package validation failed.'}
    [IO.Directory]::Move($prepared,$package)
    Write-Output "PROGRESS|install|10|$progressTotal|verify"
    Write-Output 'PASS: package built locally from the installed original game; game files untouched.'
} finally {
    if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
}

