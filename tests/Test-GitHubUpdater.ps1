Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$test=Join-Path $repo 'build\updater-test'
[void][IO.Directory]::CreateDirectory($test)
$source=Join-Path $test 'UpdaterTests.cs'
$binary=Join-Path $test 'UpdaterTests.exe'
$code=@'
using System;
using System.IO;

internal static class UpdaterTests {
    private static void Assert(bool value, string message) { if (!value) throw new Exception(message); }
    private static string Release(string tag, string state="uploaded", bool draft=false) {
        return "{\"tag_name\":\""+tag+"\",\"draft\":"+draft.ToString().ToLowerInvariant()+
            ",\"prerelease\":false,\"assets\":[{\"name\":\"HytaleArabicInstaller-0.7.0.2.exe\",\"state\":\""+state+
            "\"},{\"name\":\"SHA256.txt\",\"state\":\"uploaded\"}]}";
    }
    private static void Main() {
        var oldVersion=new Version("0.7.0.1");
        var update=GitHubUpdater.ParseRelease(Release("v0.7.0.2"),oldVersion);
        Assert(update!=null && update.Version==new Version("0.7.0.2"),"new release missing");
        Assert(update.InstallerUrl=="https://github.com/2-sa/HytaleArabic/releases/download/v0.7.0.2/HytaleArabicInstaller-0.7.0.2.exe","wrong repository URL");
        Assert(GitHubUpdater.ParseRelease(Release("v0.7.0.2"),new Version("0.7.0.2"))==null,"same version offered");
        Assert(GitHubUpdater.ParseRelease(Release("v0.7.0.1"),oldVersion)==null,"old version offered");
        Assert(GitHubUpdater.ParseRelease(Release("v0.7.0.2","pending"),oldVersion)==null,"pending asset offered");
        Assert(GitHubUpdater.ParseRelease(Release("v0.7.0.2","uploaded",true),oldVersion)==null,"draft offered");
        string name="HytaleArabicInstaller-0.7.0.2.exe";
        string hash=new string('a',64);
        Assert(GitHubUpdater.ParseChecksum(hash+"  "+name+"\n",name)==hash.ToUpperInvariant(),"checksum parse failed");
        bool rejected=false;
        try { GitHubUpdater.ParseChecksum(hash+"  other.exe\n",name); } catch(InvalidDataException) {rejected=true;}
        Assert(rejected,"wrong asset checksum accepted");
        Console.WriteLine("PASS: updater release selection, version ordering, fixed repository URL, and checksum validation");
    }
}
'@
[IO.File]::WriteAllText($source,$code,[Text.UTF8Encoding]::new($false))
& $compiler /nologo /target:exe "/out:$binary" /r:System.dll /r:System.Web.Extensions.dll (Join-Path $repo 'app\GitHubUpdater.cs') $source
if($LASTEXITCODE -ne 0){throw 'Updater tests did not compile.'}
& $binary
if($LASTEXITCODE -ne 0){throw 'Updater tests failed.'}
