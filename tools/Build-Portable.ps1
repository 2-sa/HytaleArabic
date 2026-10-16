param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$installer=[IO.Path]::GetFullPath($InstallerPath)
$output=[IO.Path]::GetFullPath($OutputPath)
if(!(Test-Path -LiteralPath $installer -PathType Leaf)){throw 'Installer is missing.'}
if(Test-Path -LiteralPath $output){throw 'Portable archive already exists.'}
$version=[Reflection.AssemblyName]::GetAssemblyName($installer).Version.ToString()
$repo=Split-Path $PSScriptRoot -Parent
$extract=Join-Path $repo ('build\portable-' + [guid]::NewGuid().ToString('N'))
$process=Start-Process -FilePath $installer -ArgumentList @('--test-extract',('"'+$extract+'"')) -PassThru -Wait -WindowStyle Hidden
if($process.ExitCode -ne 0){throw "Payload extraction failed: $($process.ExitCode)"}
if(!(Test-Path -LiteralPath (Join-Path $extract '.test-result'))){throw 'Extraction marker is missing.'}
foreach($required in @('HytaleArabicManager.exe','src\client.lang','src\server.lang','tools\ManagePackage.ps1','tools\PrepareOnDevice.ps1')){
    if(!(Test-Path -LiteralPath (Join-Path $extract $required) -PathType Leaf)){throw "Missing portable file: $required"}
}
if(Test-Path -LiteralPath (Join-Path $extract 'package')){throw 'Portable archive must not contain game assets.'}
$manager=Join-Path $extract 'HytaleArabicManager.exe'
if([Reflection.AssemblyName]::GetAssemblyName($manager).Version.ToString() -ne $version){throw 'Manager and installer versions differ.'}
Remove-Item -LiteralPath (Join-Path $extract '.test-result')
[void][IO.Directory]::CreateDirectory((Split-Path $output -Parent))
$zip=[IO.Compression.ZipFile]::Open($output,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($file in @(Get-ChildItem -LiteralPath $extract -Recurse -File | Sort-Object FullName)) {
        $name=$file.FullName.Substring($extract.Length+1).Replace('\','/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$name,[IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $zip.Dispose() }
Write-Output "PASS: built portable archive $output for $version. Nothing was installed."
