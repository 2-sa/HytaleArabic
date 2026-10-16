using System;
using System.Collections;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

internal sealed class AvailableUpdate {
    internal Version Version;
    internal string InstallerUrl;
    internal string ChecksumUrl;
    internal string InstallerName;
}

internal static class GitHubUpdater {
    private const string ReleasesApi = "https://api.github.com/repos/2-sa/HytaleArabic/releases/latest";
    private const long MaxInstallerBytes = 150L * 1024 * 1024;

    internal static AvailableUpdate Check() {
        string json = ReadText(ReleasesApi, 1024 * 1024);
        return ParseRelease(json, typeof(GitHubUpdater).Assembly.GetName().Version);
    }

    internal static AvailableUpdate ParseRelease(string json, Version current) {
        var release = new JavaScriptSerializer().DeserializeObject(json) as IDictionary;
        if (release == null || !Equals(release["draft"], false) || !Equals(release["prerelease"], false)) return null;
        string tag = release["tag_name"] as string;
        if (tag == null || !Regex.IsMatch(tag, @"^v\d+\.\d+\.\d+\.\d+$")) return null;
        Version version;
        if (!Version.TryParse(tag.Substring(1), out version) || version <= current) return null;
        string installer = "HytaleArabicInstaller-" + version + ".exe";
        var assets = release["assets"] as object[];
        if (assets == null) return null;
        bool hasInstaller = false, hasChecksum = false;
        foreach (object item in assets) {
            var asset = item as IDictionary;
            if (asset == null || !Equals(asset["state"], "uploaded")) continue;
            hasInstaller |= Equals(asset["name"], installer);
            hasChecksum |= Equals(asset["name"], "SHA256.txt");
        }
        if (!hasInstaller || !hasChecksum) return null;
        string baseUrl = "https://github.com/2-sa/HytaleArabic/releases/download/" + tag + "/";
        return new AvailableUpdate {Version=version, InstallerName=installer,
            InstallerUrl=baseUrl+installer, ChecksumUrl=baseUrl+"SHA256.txt"};
    }

    internal static string ParseChecksum(string text, string installerName) {
        foreach (string line in text.Split(new [] {'\r','\n'}, StringSplitOptions.RemoveEmptyEntries)) {
            Match match = Regex.Match(line, @"^([0-9a-fA-F]{64})  ([A-Za-z0-9.-]+)$");
            if (match.Success && match.Groups[2].Value == installerName) return match.Groups[1].Value.ToUpperInvariant();
        }
        throw new InvalidDataException("لم نجد بصمة صالحة للمُثبّت في الإصدار.");
    }

    internal static string Download(AvailableUpdate update, Action<int> progress) {
        string expected = ParseChecksum(ReadText(update.ChecksumUrl, 4096), update.InstallerName);
        string file = Path.Combine(Path.GetTempPath(), "HytaleArabicUpdate-"+update.Version+"-"+Guid.NewGuid().ToString("N")+".exe");
        try {
            var request = NewRequest(update.InstallerUrl);
            using (var response = (HttpWebResponse)request.GetResponse())
            using (var input = response.GetResponseStream())
            using (var output = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                if (response.ContentLength > MaxInstallerBytes) throw new InvalidDataException("حجم التحديث غير متوقع.");
                byte[] buffer = new byte[65536];
                long done = 0;
                int read;
                while ((read=input.Read(buffer,0,buffer.Length))>0) {
                    done += read;
                    if (done > MaxInstallerBytes) throw new InvalidDataException("حجم التحديث غير متوقع.");
                    output.Write(buffer,0,read);
                    if (response.ContentLength>0) progress(Math.Min(99,(int)(done*100/response.ContentLength)));
                }
                if (response.ContentLength>0 && done!=response.ContentLength) throw new EndOfStreamException("لم يكتمل تنزيل التحديث.");
            }
            using (var stream=File.OpenRead(file))
            using (var sha=SHA256.Create()) {
                string actual=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");
                if (!actual.Equals(expected,StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("بصمة التحديث لا تطابق الإصدار المنشور.");
            }
            if (System.Reflection.AssemblyName.GetAssemblyName(file).Version != update.Version)
                throw new InvalidDataException("رقم نسخة المُثبّت لا يطابق الإصدار المنشور.");
            progress(100);
            return file;
        } catch {
            if (File.Exists(file)) File.Delete(file);
            throw;
        }
    }

    private static string ReadText(string url, int maximum) {
        using (var response=(HttpWebResponse)NewRequest(url).GetResponse())
        using (var stream=response.GetResponseStream())
        using (var memory=new MemoryStream()) {
            byte[] buffer=new byte[4096]; int read;
            while ((read=stream.Read(buffer,0,buffer.Length))>0) {
                if (memory.Length+read>maximum) throw new InvalidDataException("ملف الإصدار أكبر من المتوقع.");
                memory.Write(buffer,0,read);
            }
            return Encoding.UTF8.GetString(memory.ToArray());
        }
    }

    private static HttpWebRequest NewRequest(string url) {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;
        var request=(HttpWebRequest)WebRequest.Create(url);
        request.UserAgent="HytaleArabicManager/1.0";
        request.Accept="application/vnd.github+json";
        request.Timeout=15000;
        request.ReadWriteTimeout=15000;
        request.AutomaticDecompression=DecompressionMethods.GZip|DecompressionMethods.Deflate;
        return request;
    }
}
