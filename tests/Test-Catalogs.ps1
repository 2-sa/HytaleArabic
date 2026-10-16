Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
$expected = @{
    'client.lang' = 3760
    'server.lang' = 11134
    'wordlists.lang' = 24
}
$expectedAvatar = 902
$total = 0
$avatar = 0
$files = @(Get-ChildItem -LiteralPath $source -Recurse -Filter '*.lang' -File)
if ($files.Count -ne 25) { throw "Expected 25 catalog files; found $($files.Count)." }

foreach ($file in $files) {
    $relative = $file.FullName.Substring($source.Length + 1).Replace('\', '/')
    $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)) {
        if ($line -notmatch '^([^=]+?) = (.*)$') { continue }
        $key = $Matches[1]
        if (!$keys.Add($key)) { throw "Duplicate key in ${relative}: $key" }
    }
    if ($relative.StartsWith('avatarCustomization/')) {
        $avatar += $keys.Count
    } elseif ($expected.ContainsKey($relative)) {
        if ($keys.Count -ne $expected[$relative]) {
            throw "Unexpected count in ${relative}: $($keys.Count); expected $($expected[$relative])."
        }
    } else {
        throw "Unexpected catalog: $relative"
    }
    $total += $keys.Count
}
if ($avatar -ne $expectedAvatar -or $total -ne 15820) {
    throw "Unexpected catalog coverage: total=$total, avatar=$avatar."
}
Write-Output "PASS: $total unique Arabic keys in $($files.Count) catalogs."

