$ErrorActionPreference='Stop'
. "$PSScriptRoot\Common.ps1"
$build=Join-Path (Split-Path $PSScriptRoot -Parent) 'build'
[void][IO.Directory]::CreateDirectory($build)
$fixtureRoot=Join-Path $build ('migration-fixture-'+[guid]::NewGuid().ToString('N'))
foreach($folder in @('old','next','arabic','old/avatarCustomization','next/avatarCustomization','arabic/avatarCustomization')){
    [void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot $folder))
}
$oldText=@'
stable = Hello {name}
changed = Hello {oldName}
removed = Removed text
missing = Missing translation
bad = Bad {name}
formatBad = Value {n, number}
caseChanged = title
multi = Line one\n \
    continued {name}
plural = {n, plural, one {one} other {{n, number} many}}
'@
$nextText=@'
stable = Hello {name}
changed = Hello {newName}
added = New {newValue}
missing = Missing translation
bad = Bad {name}
formatBad = Value {n, number}
caseChanged = Title
multi = Line one\n continued {name}
plural = {n, plural, one {one} other {{n, number} many}}
'@
$arabicText=@'
stable = مرحبًا {name}
changed = مرحبًا {oldName}
removed = النص المحذوف
bad = معرّف خاطئ {differentName}
formatBad = القيمة {n}
caseChanged = عنوان
multi = السطر الأول\n المتابعة {name}
plural = {n, plural, zero {لا عناصر} one {عنصر واحد} two {عنصران} few {{n, number} عناصر} many {{n, number} عنصرًا} other {{n, number} عنصر}}
'@
Write-Utf8 (Join-Path $fixtureRoot 'old/client.lang') $oldText
Write-Utf8 (Join-Path $fixtureRoot 'next/client.lang') $nextText
Write-Utf8 (Join-Path $fixtureRoot 'arabic/client.lang') $arabicText
Write-Utf8 (Join-Path $fixtureRoot 'old/avatarCustomization/faces.lang') 'face = Face'
Write-Utf8 (Join-Path $fixtureRoot 'next/avatarCustomization/faces.lang') 'face = Face'
Write-Utf8 (Join-Path $fixtureRoot 'arabic/avatarCustomization/faces.lang') 'face = وجه'
Write-Utf8 (Join-Path $fixtureRoot 'old/gone.lang') 'gone = Gone file'
Write-Utf8 (Join-Path $fixtureRoot 'arabic/gone.lang') 'gone = ملف محذوف'
Write-Utf8 (Join-Path $fixtureRoot 'next/new-file.lang') 'stable = Hello {name}'
$before=[ordered]@{}
foreach($file in Get-ChildItem $fixtureRoot -Recurse -File){$before[$file.FullName]=File-Hash $file.FullName}
$out=Join-Path $fixtureRoot 'result'
& "$PSScriptRoot\Migrate-TranslationSource.ps1" -OldReferenceDirectory (Join-Path $fixtureRoot 'old') -NewReferenceDirectory (Join-Path $fixtureRoot 'next') -ArabicDirectory (Join-Path $fixtureRoot 'arabic') -OutputDirectory $out -ReferenceLayout Mirrored
$report=Get-Content (Join-Path $out 'migration-report.json') -Raw | ConvertFrom-Json
foreach($pair in @{NextKeys=11;Reused=4;Added=2;Changed=2;Removed=2;UntranslatedUnchanged=1;InvalidArabic=2;Pending=7}.GetEnumerator()){
    if($report.Counts.($pair.Key) -ne $pair.Value){throw "Wrong count $($pair.Key): $($report.Counts.($pair.Key))"}
}
$reused=Read-Lang (Join-Path $out 'arabic/client.lang')
$pending=Read-Lang (Join-Path $out 'pending-english/client.lang')
if(($reused.Keys -join ',') -ne 'stable,multi,plural'){throw 'Arabic output includes stale or unrelated keys'}
if($reused.multi -cne 'السطر الأول\n المتابعة {name}'){throw 'Literal multiline escape was not preserved'}
if($pending.changed -cne 'Hello {newName}' -or $pending.added -cne 'New {newValue}'){throw 'New placeholders not preserved in pending English'}
if($pending.Contains('removed')){throw 'Removed key escaped into pending'}
if(!(Test-Path (Join-Path $out 'arabic/avatarCustomization/faces.lang'))){throw 'Nested avatar path lost'}
if((Read-Lang (Join-Path $out 'arabic/avatarCustomization/faces.lang')).face -cne 'وجه'){throw 'Nested Arabic lost'}
if(Test-Path (Join-Path $out 'arabic/gone.lang')){throw 'Removed file retained'}
if((Read-Lang (Join-Path $out 'arabic/new-file.lang')).Count -ne 0){throw 'New file borrowed Arabic from another path'}
if((Read-Lang (Join-Path $out 'pending-english/new-file.lang')).stable -cne 'Hello {name}'){throw 'Identical key/text in a different file not kept pending'}
foreach($file in $before.Keys){if((File-Hash $file) -cne $before[$file]){throw "Input overwritten: $file"}}
$refused=$false
try{& "$PSScriptRoot\Migrate-TranslationSource.ps1" -OldReferenceDirectory (Join-Path $fixtureRoot 'old') -NewReferenceDirectory (Join-Path $fixtureRoot 'next') -ArabicDirectory (Join-Path $fixtureRoot 'arabic') -OutputDirectory $out -ReferenceLayout Mirrored}catch{$refused=$true}
if(!$refused){throw 'Existing output overwrite not refused'}
# The project's flattened references map to the established src file paths.
foreach($folder in @('flat-old','flat-next','flat-arabic','flat-arabic/avatarCustomization')){[void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot $folder))}
foreach($folder in @('flat-old','flat-next')){
    Write-Utf8 (Join-Path $fixtureRoot "$folder/reference-client.lang") 'same = Same'
    Write-Utf8 (Join-Path $fixtureRoot "$folder/reference-faces.lang") 'face = Face'
}
Write-Utf8 (Join-Path $fixtureRoot 'flat-arabic/client.lang') 'same = نفسه'
Write-Utf8 (Join-Path $fixtureRoot 'flat-arabic/avatarCustomization/faces.lang') 'face = وجه'
$flatOut=Join-Path $fixtureRoot 'flat-result'
& "$PSScriptRoot\Migrate-TranslationSource.ps1" -OldReferenceDirectory (Join-Path $fixtureRoot 'flat-old') -NewReferenceDirectory (Join-Path $fixtureRoot 'flat-next') -ArabicDirectory (Join-Path $fixtureRoot 'flat-arabic') -OutputDirectory $flatOut
if(!(Test-Path (Join-Path $flatOut 'arabic/avatarCustomization/faces.lang'))){throw 'Flat avatar path mapping failed'}
Write-Host "PASS: same-key identical-English reuse, added/changed/removed fallback, changed placeholder/case rejection, missing/bad Arabic exclusion, multiline folding/escapes, nested and flat paths, unchanged input bytes, existing-output protection. Evidence: $fixtureRoot"
