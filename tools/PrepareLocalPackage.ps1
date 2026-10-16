param(
    [string]$GameRoot=(Join-Path $env:APPDATA 'Hytale'),
    [Parameter(Mandatory=$true)][string]$OriginalRoot,
    [Parameter(Mandatory=$true)][string]$ReferenceDirectory,
    [Parameter(Mandatory=$true)][string]$InterfaceDirectory,
    [Parameter(Mandatory=$true)][string]$LoadingDirectory,
    [Parameter(Mandatory=$true)][string]$WorldZip,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
. "$PSScriptRoot\Common.ps1"
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($GameRoot).TrimEnd('\')
$originalRoot=[IO.Path]::GetFullPath($OriginalRoot).TrimEnd('\')
$sharedRel='install\release\package\game\latest\Client\Data\Shared'
$shared=Join-Path $root $sharedRel
$v=Split-Path $PSScriptRoot -Parent
$probe=[IO.Path]::GetFullPath($InterfaceDirectory)
$loading=[IO.Path]::GetFullPath($LoadingDirectory)
$world=[IO.Path]::GetFullPath($WorldZip)
$prepared=[IO.Path]::GetFullPath($OutputDirectory)
$clientOriginal=Join-Path $shared 'Language\en-US\client.lang'
$actual=Read-Lang $clientOriginal
$expected=Read-Lang (Join-Path $ReferenceDirectory 'reference-client.lang')
$baselinePath=Join-Path $PSScriptRoot 'baseline-0.7.2.json'
$baseline=[IO.File]::ReadAllText($baselinePath)|ConvertFrom-Json
if($baseline.GameVersion -ne '0.7.2'){throw 'Original baseline game version differs.'}
if($baseline.EnglishClientHash -ne (File-Hash $clientOriginal)){throw 'Original client baseline differs.'}
$assetsPath=Join-Path $root 'install\release\package\game\latest\Assets.zip'
if($baseline.AssetsHash -ne (File-Hash $assetsPath)){throw 'Original asset baseline differs.'}
$baselineFiles=@{};foreach($item in $baseline.Files){$baselineFiles[$item.Relative]=$item}
foreach($item in $baseline.Files){
 if($null -eq $item.BeforeHash){continue}
 $original=Assert-Contained $originalRoot $item.Relative
 if((File-Hash $original) -ne $item.BeforeHash){throw "Original file differs from Hytale 0.7.2 baseline: $($item.Relative)"}
}
if($actual.Count -ne $expected.Count -or @($actual.Keys|Where-Object{!$expected.Contains($_) -or $actual[$_] -cne $expected[$_]}).Count){throw 'Installed English client catalog differs from 0.7.2 reference.'}
if(!(Test-Path -LiteralPath $world)){throw 'BuildWorldProbe output missing.'}
$arabicSource=Read-Lang (Join-Path $v 'src\client.lang')
$staged=Read-Lang (Join-Path $probe 'client.lang')
if($arabicSource.Count -ne 3760 -or $staged.Count -ne $actual.Count){throw 'Client source/stage count mismatch.'}
foreach($k in $arabicSource.Keys){if(!$staged.Contains($k)){throw "Missing Arabic key: $k"}}
$utf8=New-Object Text.UTF8Encoding($false)
$files=New-Object 'System.Collections.Generic.List[object]'
$stagedFiles=New-Object 'System.Collections.Generic.List[object]'
function Add-Staged([string]$relative,[string]$source){
 if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing generated file: $source"}
 $target=Assert-Contained $root $relative
 $included=Join-Path $prepared ('files\'+$relative.Replace('/','\'))
 [void][IO.Directory]::CreateDirectory((Split-Path $included -Parent))
 if(![IO.Path]::GetFullPath($source).Equals([IO.Path]::GetFullPath($included),[StringComparison]::OrdinalIgnoreCase)){
  [IO.File]::Copy($source,$included,$true)
 }
 $sourceHash=File-Hash $source
$relativeNormalized=$relative.Replace([char]92,[char]47)
if(!$baselineFiles.ContainsKey($relativeNormalized)){throw "No original baseline entry for: $relative"}
$before=$baselineFiles[$relativeNormalized].BeforeHash
if($null -ne $before -and $before -eq $sourceHash){throw "Prepared content matches original game file: $relative"}
 $stagedFiles.Add([pscustomobject]@{Relative=$relative.Replace('\','/');Source=('files/'+$relative.Replace('\','/'));BeforeHash=$before;PreparedHash=$sourceHash})
}
function Stage-Text([string]$relative,[string]$body){
 $dest=Join-Path $prepared ('files\'+$relative.Replace('/','\'))
 [void][IO.Directory]::CreateDirectory((Split-Path $dest -Parent))
 [IO.File]::WriteAllText($dest,$body,$utf8)
 Add-Staged $relative $dest
}
if(Test-Path -LiteralPath $prepared){throw 'Prepared directory already exists; inspect it before rebuilding.'}
[void][IO.Directory]::CreateDirectory($prepared)
try{
 Add-Type -Path "$PSScriptRoot\ArabicText.cs"
 Stage-Text "$sharedRel\Language\ar-SA\meta.lang" ("name = " + [ArabicText]::Visual('العربية') + "`n")
 Add-Staged "$sharedRel\Language\ar-SA\client.lang" (Join-Path $probe 'client.lang')
 $fonts=@('Lexend-Bold','NunitoSans-Medium','NunitoSans-ExtraBold','NotoSans-Bold','NotoMono-Regular')
 foreach($font in $fonts){
  foreach($ext in @('json','png')){Add-Staged "$sharedRel\UI\Fonts\$font.$ext" (Join-Path $probe "$font.$ext")}
 }
 $themeRel="$sharedRel\UI\Theme\NoesisTheme.Fonts.xaml"
 $theme=[IO.File]::ReadAllText((Assert-Contained $originalRoot $themeRel))
 if([regex]::Matches($theme,'/Fonts/#Nunito Sans,').Count -ne 1 -or $theme.Contains('/Fonts/#Arial')){throw 'Unexpected Noesis font theme.'}
 Stage-Text $themeRel ($theme.Replace('/Fonts/#Nunito Sans,','/Fonts/#Nunito Sans, /Fonts/#Arial,'))
 foreach($name in @('Fonts.xaml','Fonts.TC.xaml')){
  $rel="$sharedRel\UI\DesignSystem\$name"
  $source=[IO.File]::ReadAllText((Assert-Contained $originalRoot $rel))
  if([regex]::Matches($source,'<FontFamily x:Key="Font\.Family\.[^"]+">').Count -ne 5 -or $source.Contains('/Fonts/#Arial')){throw "Unexpected $name font dictionary."}
  $patched=[regex]::Replace($source,'(<FontFamily x:Key="Font\.Family\.[^"]+">/Fonts/#[^,]+,)', '${1} /Fonts/#Arial,')
  if([regex]::Matches($patched,'/Fonts/#Arial').Count -ne 5){throw 'Font fallback incomplete.'}
  $doc=[xml]$patched
  $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
  $ns.AddNamespace('p','http://schemas.microsoft.com/winfx/2006/xaml/presentation')
  $ns.AddNamespace('x','http://schemas.microsoft.com/winfx/2006/xaml')
  $heading=$doc.SelectSingleNode('/p:ResourceDictionary/p:FontFamily[@x:Key="Font.Family.Heading"]',$ns)
  if(!$heading -or $heading.InnerText -notmatch '/Fonts/#Arial'){throw 'Heading font fallback missing.'}
  $alias='<FontFamily x:Key="Font.LexendBold">'+$heading.InnerText+'</FontFamily>'
  $patched=$patched.Replace('</ResourceDictionary>',"    $alias`n</ResourceDictionary>")
  [void]([xml]$patched)
  Stage-Text $rel $patched
 }
 foreach($page in @('GameLoading','GameDisconnected')){
  Add-Staged "$sharedRel\UI\$page\$page.xaml" (Join-Path $loading "$page.xaml")
 }
 $arial=Join-Path $env:WINDIR 'Fonts\arial.ttf'
 if(!(Test-Path -LiteralPath $arial)){throw 'Local Arial font missing.'}
 $arialRel="$sharedRel\UI\Fonts\HytaleArabic-Windows.ttf"
$arialBaselineKey=$arialRel.Replace([char]92,[char]47)
if(!$baselineFiles.ContainsKey($arialBaselineKey) -or $null -ne $baselineFiles[$arialBaselineKey].BeforeHash){throw 'Original baseline does not mark the Arabic font as new.'}
 $stagedFiles.Add([pscustomobject]@{Relative=$arialRel.Replace('\','/');Source='@WINDOWS_ARIAL@';BeforeHash=$null;PreparedHash=(File-Hash $arial)})
 Add-Staged 'UserData\Mods\OriginalArabic-HytaleArabic.zip' $world
 foreach($f in $stagedFiles){$files.Add($f)}
 $manifest=[ordered]@{Format=1;GameVersion='0.7.2';ArabicKeys=15820;GameRoot=$root;EnglishClientHash=(File-Hash $clientOriginal);AssetsHash=(File-Hash (Join-Path $root 'install\release\package\game\latest\Assets.zip'));RuntimeVerified=$false;Files=@($files.ToArray())}
 [IO.File]::WriteAllText((Join-Path $prepared 'manifest.json'),($manifest|ConvertTo-Json -Depth 7),$utf8)
 Write-Output "PASS: prepared $($files.Count) files for locally installed Hytale 0.7.2; no game file modified."
}catch{throw}
