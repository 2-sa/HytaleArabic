param(
    [Parameter(Mandatory=$true)][string]$Archive,
    [Parameter(Mandatory=$true)][string]$Version
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$test=Join-Path $repo ('build\portable-update-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($test)
$source=Join-Path $test 'PortableTests.cs'
$binary=Join-Path $test 'PortableTests.exe'
$copy=Join-Path $test 'update.zip'
Copy-Item -LiteralPath $Archive -Destination $copy
$code=@'
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

internal static class PortableTests {
    private static void Assert(bool condition,string message) {if(!condition)throw new Exception(message);}
    private static void Main(string[] args) {
        Version version=new Version(args[1]);
        string manager=GitHubUpdater.ExtractPortable(args[0],version);
        string root=Path.GetDirectoryName(manager);
        Assert(AssemblyName.GetAssemblyName(manager).Version==version,"wrong manager version");
        Assert(File.Exists(Path.Combine(root,"tools","PrepareOnDevice.ps1")),"missing preparation tool");
        Assert(File.Exists(Path.Combine(root,"src","server.lang")),"missing translation source");
        Assert(!Directory.Exists(Path.Combine(root,"package")),"game package bundled");
        Assert(!File.Exists(args[0]),"temporary archive retained");
        string attack=Path.Combine(Path.GetDirectoryName(args[0]),"unsafe.zip");
        using(var zip=ZipFile.Open(attack,ZipArchiveMode.Create)) {
            using(var writer=new StreamWriter(zip.CreateEntry("../escape.txt").Open()))writer.Write("unsafe");
        }
        bool rejected=false;
        try{GitHubUpdater.ExtractPortable(attack,version);}catch(InvalidDataException){rejected=true;}
        Assert(rejected,"unsafe archive path accepted");
        Assert(!File.Exists(Path.Combine(Path.GetDirectoryName(root),"escape.txt")),"archive escaped destination");
        Console.WriteLine("PASS: portable update extraction, version, source files, and unsafe path rejection");
    }
}
'@
[IO.File]::WriteAllText($source,$code,[Text.UTF8Encoding]::new($false))
& $compiler /nologo /target:exe "/out:$binary" /r:System.dll /r:System.Web.Extensions.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll (Join-Path $repo 'app\GitHubUpdater.cs') $source
if($LASTEXITCODE -ne 0){throw 'Portable update tests did not compile.'}
& $binary $copy $Version
if($LASTEXITCODE -ne 0){throw 'Portable update tests failed.'}
