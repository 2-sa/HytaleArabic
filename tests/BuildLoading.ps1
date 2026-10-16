param(
    [string]$GameRoot=(Join-Path $env:APPDATA 'Hytale'),
    [Parameter(Mandatory=$true)][string]$OriginalShared,
    [Parameter(Mandatory=$true)][string]$InterfaceDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
. "$PSScriptRoot\..\tools\Common.ps1"
$shared=Join-Path $GameRoot 'install\release\package\game\latest\Client\Data\Shared'
$out=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $out | Out-Null
foreach($page in @('GameLoading','GameDisconnected')) {
 $relative="UI\$page\$page.xaml"
 $source=Join-Path $OriginalShared $relative
 $text=[IO.File]::ReadAllText($source)
 $patched=[regex]::Replace($text,'<TextBlock(?=\s|>)[^>]*>',[Text.RegularExpressions.MatchEvaluator]{param($match)
  if($match.Value -match '\bFontFamily=') {return $match.Value}
  return $match.Value.Replace('<TextBlock','<TextBlock FontFamily="{StaticResource Font.Family.Body}"')
 })
 $doc=[xml]$patched
 $ns=New-Object Xml.XmlNamespaceManager($doc.NameTable)
 $ns.AddNamespace('p','http://schemas.microsoft.com/winfx/2006/xaml/presentation')
 foreach($block in $doc.SelectNodes('//p:TextBlock',$ns)) {if(!$block.HasAttribute('FontFamily')){throw 'Loading text has no explicit font family.'}}
 Write-Utf8 (Join-Path $out "$page.xaml") $patched
 Write-Utf8 (Join-Path $out "$page.before.sha256") (File-Hash $source)
}
$sourceLang=Read-Lang "$PSScriptRoot\..\src\client.lang"
$stagedLang=Read-Lang (Join-Path $InterfaceDirectory 'client.lang')
foreach($key in $sourceLang.Keys | Where-Object {$_ -match '^(gameLoadingView|disconnection)\.'}) {
 if($sourceLang[$key] -cne $stagedLang[$key]) {throw "Native loading text was pre-shaped: $key"}
}
Write-Host 'PASS: loading/disconnection text stays logical; all page TextBlocks have explicit Arabic-capable families.'
