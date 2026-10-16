param(
    [string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$AppVersion='0.7.0.0'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path $PSScriptRoot -Parent
$package = if($PackageRoot){[IO.Path]::GetFullPath($PackageRoot)}else{$null}
$output = [IO.Path]::GetFullPath($OutputPath)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$manifestPath = if($package){Join-Path $package 'manifest.json'}else{$null}
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Windows .NET Framework C# compiler is missing.' }
if($AppVersion -notmatch '^\d+\.\d+\.\d+\.\d+$'){throw 'AppVersion must have four numeric parts.'}
if (Test-Path -LiteralPath $output) { throw 'Output installer already exists; choose a new path.' }
if($package){
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Local package manifest is missing.' }
    $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($manifest.Format -ne 1 -or $manifest.GameVersion -ne '0.7.0' -or $manifest.Files.Count -ne 19) {
        throw 'This builder requires a complete Hytale 0.7.0 package.'
    }
    foreach ($entry in $manifest.Files) {
        if ($entry.Source -eq '@WINDOWS_ARIAL@') { continue }
        $relative = [string]$entry.Source
        if (!$relative.StartsWith('files/') -or $relative.Contains('..') -or [IO.Path]::IsPathRooted($relative)) {
            throw "Unsafe package source: $relative"
        }
        $source = Join-Path $package ($relative.Replace('/', '\'))
        if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package file: $relative" }
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($hash -ne $entry.PreparedHash) { throw "Package hash mismatch: $relative" }
    }
}

$build = Join-Path $repo ('build\installer-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $build 'payload'
$payloadTools = Join-Path $payload 'tools'
[void][IO.Directory]::CreateDirectory($payloadTools)
if($package){
    Copy-Item -LiteralPath $package -Destination (Join-Path $payload 'package') -Recurse
    $toolNames=@('Common.ps1','ManagePackage.ps1')
}else{
    Copy-Item -LiteralPath (Join-Path $repo 'src') -Destination (Join-Path $payload 'src') -Recurse
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'tests'))
    foreach($name in @('BuildInterface.ps1','BuildWorld.ps1','BuildLoading.ps1')){
        Copy-Item -LiteralPath (Join-Path $repo "tests\$name") -Destination (Join-Path $payload 'tests')
    }
    $toolNames=@('Common.ps1','ManagePackage.ps1','PrepareOnDevice.ps1','PrepareLocalPackage.ps1','SnapshotGameReferences.ps1','ArabicText.cs','FontAtlas.cs','baseline-0.7.0.json')
}
foreach($name in $toolNames){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $payloadTools}
Copy-Item -LiteralPath (Join-Path $repo 'README.md') -Destination (Join-Path $payload 'README.txt')

$assemblyInfo=Join-Path $build 'AssemblyInfo.cs'
[IO.File]::WriteAllText($assemblyInfo, "using System.Reflection; [assembly: AssemblyVersion(`"$AppVersion`")] [assembly: AssemblyFileVersion(`"$AppVersion`")]", [Text.UTF8Encoding]::new($false))

$manager = Join-Path $payload 'HytaleArabicManager.exe'
& $compiler /nologo /target:winexe "/out:$manager" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll $assemblyInfo (Join-Path $repo 'app\HytaleArabicManager.cs')
if ($LASTEXITCODE -ne 0) { throw 'Manager compilation failed.' }

$archivePath = Join-Path $build 'payload.zip'
$listPath = Join-Path $build 'payload.sha256'
$archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
$hashes = [Collections.Generic.List[string]]::new()
try {
    foreach ($file in @(Get-ChildItem -LiteralPath $payload -Recurse -File | Sort-Object FullName)) {
        $name = $file.FullName.Substring($payload.Length + 1).Replace('\', '/')
        if ($name.Contains('|') -or $name.Contains('..')) { throw "Unsafe payload path: $name" }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
        $hashes.Add($name + '|' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)
    }
} finally { $archive.Dispose() }
[IO.File]::WriteAllLines($listPath, $hashes.ToArray(), [Text.UTF8Encoding]::new($false))

[void][IO.Directory]::CreateDirectory((Split-Path $output -Parent))
$zipResource = '/resource:' + $archivePath + ',HytaleArabic.Payload'
$hashResource = '/resource:' + $listPath + ',HytaleArabic.Manifest'
& $compiler /nologo /target:winexe "/out:$output" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll $zipResource $hashResource $assemblyInfo (Join-Path $repo 'installer\HytaleArabicSetup.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Write-Output "PASS: built $output with $($hashes.Count) verified payload files. Nothing was installed."

