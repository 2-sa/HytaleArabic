param(
 [string]$SourceRoot = (Join-Path $PSScriptRoot '..\src'),
 [string]$ReferenceRoot = (Join-Path $PSScriptRoot 'reference-snapshot-audit'),
 [string]$OutputRoot = (Join-Path $PSScriptRoot 'linguistic-audit')
)

$ErrorActionPreference = 'Stop'
[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputRoot)) | Out-Null
$pattern = '^([^=]+?) = (.*)$'
$markers = [ordered]@{
 'auxiliary-passive' = '(?:^|\s)تم(?:ت)?\s'
 'polite-noise' = 'يرجى|الرجاء|قم ب|قومي ب'
 'translationese-form' = 'بشكل\s|بصورة\s|من خلال|على مستوى|في الوقت الحالي|في نهاية المطاف|يلعب دور|تسليط الضوء|الخاص بك|الخاصة بك'
 'pseudo-existential' = '(?:^|\s)هناك\s'
 'awkward-quantity' = '\b(?:واحد|اثنان|اثنين)\s+(?:عنصر|ملف|لاعب|نقطة|سلاح)'
}
$summary = [ordered]@{Catalogs=@(); TotalArabicEntries=0; TotalMissingEnglish=0; TotalMissingArabic=0; TotalPlaceholderMismatches=0; TotalFlags=0}
$flagLines = [Collections.Generic.List[string]]::new()
$flagLines.Add("Catalog`tLine`tKey`tFlag`tArabic`tEnglish")

function Parse-Catalog([string]$path) {
 $map = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 $duplicates = [Collections.Generic.List[string]]::new()
 $lines = [IO.File]::ReadAllLines([IO.Path]::GetFullPath($path),[Text.Encoding]::UTF8)
 for ($i=0; $i -lt $lines.Length; $i++) {
  $line = $lines[$i]
  if ($line -notmatch $pattern) { continue }
  $key = $Matches[1]; $value = $Matches[2]
  while ($value.EndsWith('\') -and $i + 1 -lt $lines.Length) {
   $value = $value.Substring(0,$value.Length-1) + $lines[++$i]
  }
  if ($map.ContainsKey($key)) { $duplicates.Add($key); continue }
  $map[$key] = [pscustomobject]@{Value=$value;Line=($i+1)}
 }
 return [pscustomobject]@{Map=$map;Duplicates=@($duplicates)}
}

function Get-Placeholders([string]$value) {
 $normalized = [regex]::Replace($value,'([,}])\s*(?:undo|redo|set|biome|zone|region|prefab)\s+\{','$1')
 $normalized = [regex]::Replace($normalized,'\b(?:zero|one|two|few|many|other|true|false)\s+\{','')
 $names = @([regex]::Matches($normalized,'\{([A-Za-z_][A-Za-z0-9_]*)\s*(?:[,}])') | ForEach-Object { $_.Groups[1].Value })
 return (($names | Sort-Object -Unique) -join ',')
}

foreach ($catalog in @('client','server')) {
 $ar = Parse-Catalog (Join-Path $SourceRoot "$catalog.lang")
 $en = Parse-Catalog (Join-Path $ReferenceRoot "reference-$catalog.lang")
 $missingEnglish = @($ar.Map.Keys | Where-Object { !$en.Map.ContainsKey($_) })
 $missingArabic = @($en.Map.Keys | Where-Object { !$ar.Map.ContainsKey($_) })
 $placeholderMismatches = [Collections.Generic.List[string]]::new()
 $flagCount = 0
 foreach ($key in $ar.Map.Keys) {
  $arabic = [string]$ar.Map[$key].Value
  $english = if ($en.Map.ContainsKey($key)) { [string]$en.Map[$key].Value } else { '' }
  $flags = [Collections.Generic.List[string]]::new()
  if (!$en.Map.ContainsKey($key)) { $flags.Add('not-in-English-reference') }
  elseif ((Get-Placeholders $arabic) -ne (Get-Placeholders $english)) {
   $flags.Add('placeholder-mismatch')
   $placeholderMismatches.Add($key)
  }
  if ($arabic -eq $english -and $arabic -match '[A-Za-z]{4,}') { $flags.Add('untranslated-or-name') }
  foreach ($marker in $markers.Keys) { if ($arabic -match $markers[$marker]) { $flags.Add($marker) } }
  if ($arabic -notmatch '[\u0600-\u06FF]' -and $arabic -match '[A-Za-z]{4,}') { $flags.Add('no-Arabic') }
  if ($flags.Count -eq 0) { continue }
  $flagCount += $flags.Count
  $safeArabic = $arabic -replace "`t|`r|`n",' '
  $safeEnglish = $english -replace "`t|`r|`n",' '
  foreach ($flag in $flags) { $flagLines.Add("$catalog`t$($ar.Map[$key].Line)`t$key`t$flag`t$safeArabic`t$safeEnglish") }
 }
 $summary.Catalogs += [ordered]@{
  Name=$catalog;ArabicEntries=$ar.Map.Count;EnglishEntries=$en.Map.Count
  ArabicDuplicates=@($ar.Duplicates);EnglishDuplicates=@($en.Duplicates)
  MissingEnglish=@($missingEnglish);MissingArabic=@($missingArabic)
  PlaceholderMismatches=@($placeholderMismatches);FlagCount=$flagCount
 }
 $summary.TotalArabicEntries += $ar.Map.Count
 $summary.TotalMissingEnglish += $missingEnglish.Count
 $summary.TotalMissingArabic += $missingArabic.Count
 $summary.TotalPlaceholderMismatches += $placeholderMismatches.Count
 $summary.TotalFlags += $flagCount
}

$out=[IO.Path]::GetFullPath($OutputRoot)
[IO.File]::WriteAllLines((Join-Path $out 'priority-review.tsv'),$flagLines,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $out 'structural-report.json'),($summary|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output "Audited $($summary.TotalArabicEntries) Arabic entries; placeholders=$($summary.TotalPlaceholderMismatches); flags=$($summary.TotalFlags)."
Write-Output "Output: $out"
