param(
    [string]$GameRoot=(Join-Path $env:APPDATA 'Hytale'),
    [Parameter(Mandatory=$true)][string]$FontDirectory,
    [Parameter(Mandatory=$true)][string]$ReferenceDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
. "$PSScriptRoot\..\tools\Common.ps1"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -Path "$PSScriptRoot\..\tools\ArabicText.cs"
$out=[IO.Path]::GetFullPath($OutputDirectory)
$stage=Join-Path $out ('stage-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'Server\Languages\ar-SA') | Out-Null
$expectedServer=Read-Lang (Join-Path $ReferenceDirectory 'reference-server.lang')
$expectedWordlist=Read-Lang (Join-Path $ReferenceDirectory 'reference-wordlists.lang')
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $GameRoot 'install\release\package\game\latest\Assets.zip'))
try {
 $entry=$zip.GetEntry('Server/Languages/en-US/server.lang')
 if(!$entry) { throw 'Missing world language source.' }
 $reader=New-Object IO.StreamReader($entry.Open())
 try { $text=$reader.ReadToEnd() } finally { $reader.Dispose() }
 $wordlistEntry=$zip.GetEntry('Server/Languages/en-US/wordlists.lang')
 if(!$wordlistEntry) {throw 'Missing world wordlist source.'}
 $wordlistReader=New-Object IO.StreamReader($wordlistEntry.Open())
 try {$wordlistText=$wordlistReader.ReadToEnd()} finally {$wordlistReader.Dispose()}
} finally { $zip.Dispose() }
$reference=Join-Path $stage 'reference.lang'
Write-Utf8 $reference $text
$actualServer=Read-Lang $reference
if($actualServer.Count -ne $expectedServer.Count -or @($actualServer.Keys | Where-Object { !$expectedServer.Contains($_) -or $actualServer[$_] -cne $expectedServer[$_] }).Count) { throw 'World language version mismatch.' }
$map=Read-Lang $reference
Remove-Item -LiteralPath $reference
$patch=Read-Lang "$PSScriptRoot\..\src\server.lang"
$characters=New-Object 'System.Collections.Generic.HashSet[int]'
$wordlistReference=Join-Path $stage 'wordlists-reference.lang'
Write-Utf8 $wordlistReference $wordlistText
$actualWordlist=Read-Lang $wordlistReference
if($actualWordlist.Count -ne $expectedWordlist.Count -or @($actualWordlist.Keys | Where-Object { !$expectedWordlist.Contains($_) -or $actualWordlist[$_] -cne $expectedWordlist[$_] }).Count) { throw 'World wordlist version mismatch.' }
$wordlistMap=Read-Lang $wordlistReference
Remove-Item -LiteralPath $wordlistReference
$wordlistPatch=Read-Lang "$PSScriptRoot\..\src\wordlists.lang"
foreach($key in $wordlistPatch.Keys) {
 if(!$wordlistMap.Contains($key)) {throw "Unknown wordlist key: $key"}
 $wordlistMap[$key]=[ArabicText]::Visual($wordlistPatch[$key])
 foreach($c in $wordlistMap[$key].ToCharArray()) {if(([int]$c -ge 0x0600 -and [int]$c -le 0x06FF) -or ([int]$c -ge 0xFE70 -and [int]$c -le 0xFEFF)) {[void]$characters.Add([int]$c)}}
}
Write-Lang (Join-Path $stage 'Server\Languages\ar-SA\wordlists.lang') $wordlistMap
foreach($key in $patch.Keys) {
 if(!$map.Contains($key)) { throw "Unknown key $key" }
 $logical=$patch[$key]
 $visual=(@($logical -split '\\n' | ForEach-Object { [ArabicText]::Visual($_) }) -join '\n')
 $map[$key]=if($logical -match '[<{]') { $logical } else { $visual }
 foreach($c in $map[$key].ToCharArray()) { if(([int]$c -ge 0x0600 -and [int]$c -le 0x06FF) -or ([int]$c -ge 0xFE70 -and [int]$c -le 0xFEFF)) { [void]$characters.Add([int]$c) } }
}
$avatarCount=0
foreach($file in Get-ChildItem "$PSScriptRoot\..\src\avatarCustomization" -Filter '*.lang') {
 $avatar=Read-Lang $file.FullName
 $base=Read-Lang (Join-Path $ReferenceDirectory ('reference-'+$file.Name))
 foreach($key in $avatar.Keys) {
  if(!$base.Contains($key)) { throw 'Unknown avatar key.' }
  $base[$key]=[ArabicText]::Visual($avatar[$key])
  foreach($c in $base[$key].ToCharArray()) { if(([int]$c -ge 0x0600 -and [int]$c -le 0x06FF) -or ([int]$c -ge 0xFE70 -and [int]$c -le 0xFEFF)) { [void]$characters.Add([int]$c) } }
 }
 $avatarDir=Join-Path $stage 'Common\Languages\ar-SA\avatarCustomization'
 New-Item -ItemType Directory -Force -Path $avatarDir | Out-Null
 Write-Lang (Join-Path $avatarDir $file.Name) $base
 $avatarCount+=$avatar.Count
}
$shared=Join-Path $GameRoot 'install\release\package\game\latest\Client\Data\Shared'
if(!$FontDirectory) { $FontDirectory=Join-Path $shared 'UI\Fonts' }
$missing=@{}
foreach($font in @('Lexend-Bold','NunitoSans-Medium','NunitoSans-ExtraBold','NotoSans-Bold','NotoMono-Regular')) {
 $data=Get-Content -LiteralPath (Join-Path $FontDirectory "$font.json") -Raw | ConvertFrom-Json
 $available=@($data.glyphs | ForEach-Object unicode)
 $absent=@($characters | Where-Object { $available -notcontains $_ })
 if($absent.Count) { $missing[$font]=$absent }
}
if($missing.Count) { Write-Utf8 (Join-Path $out 'missing-glyphs.json') ($missing | ConvertTo-Json); throw 'World texts require additional font forms; package not built.' }
Write-Lang (Join-Path $stage 'Server\Languages\ar-SA\server.lang') $map
$pack=[ordered]@{Group='OriginalArabic';Name='HytaleArabic';Version='0.7.2';Description='تعريب عربي أصلي لنصوص العالم وتخصيص الشخصية';Authors=@(@{Name='Arabic localization project'});ServerVersion='=0.7.2';IncludesAssetPack=$true}
Write-Utf8 (Join-Path $stage 'manifest.json') ($pack | ConvertTo-Json -Depth 5)
$target=Join-Path $out 'OriginalArabic-HytaleArabic.zip'
if(Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
# Windows PowerShell's CreateFromDirectory writes backslashes on this runtime.
# The game's asset paths use forward slashes even on Windows.
$outputZip=[IO.Compression.ZipFile]::Open($target,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
  $entryName=$file.FullName.Substring($stage.Length+1).Replace('\','/')
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($outputZip,$file.FullName,$entryName,[IO.Compression.CompressionLevel]::Optimal)
 }
} finally { $outputZip.Dispose() }
$checkZip=[IO.Compression.ZipFile]::OpenRead($target)
try {
 if(!$checkZip.GetEntry('Server/Languages/ar-SA/server.lang')) { throw 'Canonical world language entry missing.' }
 if(@($checkZip.Entries | Where-Object { $_.FullName.Contains('\') }).Count) { throw 'Invalid ZIP entry separator.' }
} finally { $checkZip.Dispose() }
# Exact local stage path, checked before recursive cleanup.
$checkedStage=Assert-Contained $out (Split-Path $stage -Leaf)
Remove-Item -LiteralPath $checkedStage -Recurse -Force
Write-Host "PASS: $($patch.Count) world + $avatarCount avatar strings; $($characters.Count) Arabic forms available in all five fonts."
