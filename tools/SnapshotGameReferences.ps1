param(
    [Parameter(Mandatory=$true)][string]$GameDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$game = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
if ($output.Equals($game,[StringComparison]::OrdinalIgnoreCase) -or $output.StartsWith($game+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Output must be outside the game installation.' }
if (Test-Path -LiteralPath $output) { throw 'Output already exists; choose a new snapshot directory.' }
$client = Join-Path $game 'Client/Data/Shared/Language/en-US/client.lang'
$assets = Join-Path $game 'Assets.zip'
if (!(Test-Path -LiteralPath $client -PathType Leaf)) { throw 'English client catalog is missing.' }
$clientBytes = [IO.File]::ReadAllBytes($client)
$archive = [IO.Compression.ZipFile]::OpenRead($assets)
$catalogs = [ordered]@{'reference-client.lang'=$clientBytes}
try {
    foreach ($entry in $archive.Entries) {
        $name = $null
        if ($entry.FullName -cmatch '^Server/Languages/en-US/(server|wordlists)\.lang$') { $name = 'reference-'+$matches[1]+'.lang' }
        elseif ($entry.FullName -cmatch '^Common/Languages/en-US/avatarCustomization/([A-Za-z0-9_-]+)\.lang$') { $name = 'reference-'+$matches[1]+'.lang' }
        if (!$name) { continue }
        if ($catalogs.Contains($name)) { throw "Duplicate catalog: $name" }
        $stream = $entry.Open()
        $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory); $catalogs[$name]=$memory.ToArray() }
        finally { $stream.Dispose(); $memory.Dispose() }
    }
} finally { $archive.Dispose() }
foreach ($required in @('reference-server.lang','reference-wordlists.lang')) {
    if (!$catalogs.Contains($required)) { throw "Missing catalog: $required" }
}
if ($catalogs.Count -le 3) { throw 'No avatar catalogs found; inspect the new asset layout.' }
# Nothing is written until the complete input set has been validated.
[void][IO.Directory]::CreateDirectory($output)
$files = foreach ($name in $catalogs.Keys) {
    $path = Join-Path $output $name
    [IO.File]::WriteAllBytes($path,$catalogs[$name])
    [ordered]@{File=$name; SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
$report = [ordered]@{
    Format=1; GeneratedUtc=[DateTime]::UtcNow.ToString('o'); CatalogFiles=$catalogs.Count
    GameModified=$false; ForLocalComparisonOnly=$true; Files=@($files)
}
[IO.File]::WriteAllText((Join-Path $output 'snapshot.json'),($report|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
Write-Output "PASS: $($catalogs.Count) original English catalogs copied for local comparison; game files untouched."
