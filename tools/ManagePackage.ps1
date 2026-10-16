param(
 [ValidateSet('status','install','restore')][string]$Action='status',
 [string]$GameRoot=(Join-Path $env:APPDATA 'Hytale'),
 [string]$PackageRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'package')
)
. "$PSScriptRoot\Common.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$package=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')
$manifestPath=Join-Path $package 'manifest.json'
$stateDir=Join-Path $root 'UserData\HytaleArabicManager'
$statePath=Join-Path $stateDir 'state.json'
function Save-State($state){
 [void][IO.Directory]::CreateDirectory($stateDir)
 $temp=Join-Path $stateDir ('state-'+[guid]::NewGuid().ToString('N')+'.tmp')
 $replaced=Join-Path $stateDir ('state-replaced-'+[guid]::NewGuid().ToString('N')+'.tmp')
 Write-Utf8 $temp ($state|ConvertTo-Json -Depth 8)
 try {if(Test-Path -LiteralPath $statePath){[IO.File]::Replace($temp,$statePath,$replaced)}else{[IO.File]::Move($temp,$statePath)}}
 finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp};if(Test-Path -LiteralPath $replaced){Remove-Item -LiteralPath $replaced}}
}
function Source-Path($item){
 if($item.Source -eq '@WINDOWS_ARIAL@'){return (Join-Path $env:WINDIR 'Fonts\arial.ttf')}
 return (Assert-Contained $package $item.Source)
}
function Copy-Atomic([string]$source,[string]$target){
 [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
 $temp=Join-Path (Split-Path $target -Parent) ([IO.Path]::GetFileName($target)+'.arabic-'+[guid]::NewGuid().ToString('N')+'.tmp')
 $replaced=Join-Path (Split-Path $target -Parent) ([IO.Path]::GetFileName($target)+'.replaced-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  [IO.File]::Copy($source,$temp)
  if(Test-Path -LiteralPath $target){[IO.File]::Replace($temp,$target,$replaced)}else{[IO.File]::Move($temp,$target)}
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp};if(Test-Path -LiteralPath $replaced){Remove-Item -LiteralPath $replaced}}
}
function Progress-Line([string]$operation,[int]$done,[int]$total,[string]$stage){
 if($operation -eq 'install' -and $script:installOffset -gt 0){$done+=$script:installOffset;$total+=$script:installOffset}
 Write-Output "PROGRESS|$operation|$done|$total|$stage"
}
$script:installOffset=0
$current=$null
if(Test-Path -LiteralPath $statePath){$current=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json}
if($Action -eq 'status'){
 $status=if($null -eq $current){'not-installed'}else{$current.Status}
 Write-Output "Localization: $status; package 0.7.0; 15819 source keys."
 return
}
Assert-Closed
if($Action -eq 'install'){
 if($null -ne $current -and $current.Status -ne 'removed'){throw 'Existing localization transaction must be restored first.'}
 if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)){
  & (Join-Path $PSScriptRoot 'PrepareOnDevice.ps1') -GameRoot $root -PackageRoot $package
  if(!$?){throw 'Local package preparation failed.'}
  $script:installOffset=10
 }
 $manifest=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json
 if($manifest.Format -ne 1 -or $manifest.GameVersion -ne '0.7.0' -or $manifest.GameRoot -ne $root -or $manifest.Files.Count -ne 19){throw 'Prepared package identity does not match this installation.'}
 $installTotal=($manifest.Files.Count*3)+@($manifest.Files|Where-Object{$null -ne $_.BeforeHash}).Count
 $step=0
 Progress-Line 'install' $step $installTotal 'version'
 $client=Assert-Contained $root 'install\release\package\game\latest\Client\Data\Shared\Language\en-US\client.lang'
 $assets=Assert-Contained $root 'install\release\package\game\latest\Assets.zip'
 if((File-Hash $client) -ne $manifest.EnglishClientHash -or (File-Hash $assets) -ne $manifest.AssetsHash){throw 'Game version changed; this 0.7.0 package will not be installed.'}
 $records=New-Object 'System.Collections.Generic.List[object]'
 foreach($item in $manifest.Files){
  $target=Assert-Contained $root $item.Relative
  $source=Source-Path $item
  if((File-Hash $target) -ne $item.BeforeHash -or (File-Hash $source) -ne $item.PreparedHash){throw "File validation failed: $($item.Relative)"}
  $records.Add([pscustomobject]@{Relative=$item.Relative;BeforeHash=$item.BeforeHash;PreparedHash=$item.PreparedHash;Source=$item.Source})
  $step++;Progress-Line 'install' $step $installTotal 'check'
 }
 [void][IO.Directory]::CreateDirectory((Join-Path $stateDir 'original'))
 foreach($item in $records){
  if($null -eq $item.BeforeHash){continue}
  $origin=Assert-Contained (Join-Path $stateDir 'original') $item.Relative
  [void][IO.Directory]::CreateDirectory((Split-Path $origin -Parent))
  [IO.File]::Copy((Assert-Contained $root $item.Relative),$origin,$true)
  if((File-Hash $origin) -ne $item.BeforeHash){throw 'Original backup verification failed.'}
  $step++;Progress-Line 'install' $step $installTotal 'backup'
 }
 $state=[ordered]@{Format=1;Status='installing';GameVersion='0.7.0';Root=$root;Files=@($records.ToArray())}
 Save-State $state
 try{
  foreach($item in $records){Copy-Atomic (Source-Path $item) (Assert-Contained $root $item.Relative);$step++;Progress-Line 'install' $step $installTotal 'apply'}
  foreach($item in $records){if((File-Hash (Assert-Contained $root $item.Relative)) -ne $item.PreparedHash){throw 'Post-install hash verification failed.'};$step++;Progress-Line 'install' $step $installTotal 'verify'}
  $state.Status='installed';Save-State $state
  Write-Output 'PASS: Arabic 0.7.0 files installed with verified original backups.'
 }catch{
  Write-Warning 'Installation interrupted. Use Restore in the manager before updating the game.'
  throw
 }
 return
}
if($null -eq $current -or $current.Status -eq 'removed'){Write-Output 'Localization is already removed.';return}
if($current.Format -ne 1 -or $current.Root -ne $root -or $current.GameVersion -ne '0.7.0' -or $current.Files.Count -ne 19){throw 'Recovery record does not match this game.'}
if($current.Status -notin @('installed','installing','restoring')){throw 'Unknown recovery state.'}
$restoreTotal=$current.Files.Count*3
$step=0
Progress-Line 'restore' $step $restoreTotal 'check'
# Accept both endpoints: a prior process might have stopped between atomic file changes.
foreach($item in $current.Files){
 $target=Assert-Contained $root $item.Relative
 $observed=File-Hash $target
 if($observed -ne $item.BeforeHash -and $observed -ne $item.PreparedHash){throw "Changed game file; recovery stopped: $($item.Relative)"}
 if($null -ne $item.BeforeHash){
  $origin=Assert-Contained (Join-Path $stateDir 'original') $item.Relative
  if((File-Hash $origin) -ne $item.BeforeHash){throw "Original backup mismatch: $($item.Relative)"}
 }
 $step++;Progress-Line 'restore' $step $restoreTotal 'check'
}
$current.Status='restoring';Save-State $current
foreach($item in $current.Files){
 $target=Assert-Contained $root $item.Relative
 if($null -ne $item.BeforeHash){
  if((File-Hash $target) -ne $item.BeforeHash){Copy-Atomic (Assert-Contained (Join-Path $stateDir 'original') $item.Relative) $target}
 }elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}
 $step++;Progress-Line 'restore' $step $restoreTotal 'restore'
}
foreach($item in $current.Files){if((File-Hash (Assert-Contained $root $item.Relative)) -ne $item.BeforeHash){throw 'Post-restore verification failed.'};$step++;Progress-Line 'restore' $step $restoreTotal 'verify'}
$current.Status='removed';Save-State $current
Write-Output 'PASS: original game files restored; official launcher may now update.'
