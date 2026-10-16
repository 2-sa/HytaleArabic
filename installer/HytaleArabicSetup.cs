using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class SetupProgram {
    internal const string AppName = "تعريب هايتل";
    internal static readonly string AppVersion = Assembly.GetExecutingAssembly().GetName().Version.ToString();
    internal static readonly string InstallRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Programs", "HytaleArabicManager");
    internal static readonly string StartShortcut = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Microsoft", "Windows", "Start Menu", "Programs", AppName + ".lnk");
    internal static readonly string DesktopShortcut = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), AppName + ".lnk");
    internal const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\HytaleArabicManager";
    internal const string Marker = ".hytale-arabic-managed";
    internal const string FileList = ".install-manifest";

    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool MoveFileEx(string existing, string replacement, int flags);

    [STAThread]
    private static void Main(string[] args) {
        if (args.Length == 2 && args[0] == "--test-extract") {
            try {
                if (Directory.Exists(args[1])) throw new IOException("Test destination already exists.");
                Directory.CreateDirectory(args[1]);
                Payload.Extract(args[1], null);
                File.WriteAllText(Path.Combine(args[1], ".test-result"), "PASS", Encoding.UTF8);
                Environment.ExitCode = 0;
            } catch (Exception ex) {
                try { File.WriteAllText(Path.Combine(args[1], ".test-error"), ex.ToString()); } catch {}
                Environment.ExitCode = 1;
            }
            return;
        }
        if (args.Length > 0 && args[0] == "--uninstall") {
            try {
                string temporary = Path.Combine(Path.GetTempPath(), "HytaleArabicUninstall-" + Guid.NewGuid().ToString("N") + ".exe");
                File.Copy(Assembly.GetExecutingAssembly().Location, temporary);
                Process.Start(new ProcessStartInfo(temporary, "--uninstall-internal") { UseShellExecute=true });
            } catch (Exception ex) { MessageBox.Show("تعذّر بدء الإزالة: " + ex.Message, AppName); }
            return;
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        bool removing = args.Length > 0 && args[0] == "--uninstall-internal";
        Application.Run(new SetupWindow(removing));
        if (removing) MoveFileEx(Assembly.GetExecutingAssembly().Location, null, 4);
    }

    internal static void MakeShortcut(string shortcutPath, string target) {
        Type type = Type.GetTypeFromProgID("WScript.Shell");
        if (type == null) throw new Exception("تعذّر إنشاء الاختصار في Windows.");
        object shell = Activator.CreateInstance(type);
        object link = null;
        try {
            link = type.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] {shortcutPath});
            Type linkType = link.GetType();
            linkType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] {target});
            linkType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] {Path.GetDirectoryName(target)});
            linkType.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] {AppName});
            linkType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, link, new object[] {target + ",0"});
            linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        } finally {
            if (link != null && Marshal.IsComObject(link)) Marshal.ReleaseComObject(link);
            if (Marshal.IsComObject(shell)) Marshal.ReleaseComObject(shell);
        }
    }

    internal static bool GameTranslationInstalled() {
        string state = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Hytale", "UserData", "HytaleArabicManager", "state.json");
        if (!File.Exists(state)) return false;
        string json = File.ReadAllText(state, Encoding.UTF8);
        return Regex.IsMatch(json, "\"Status\"\\s*:\\s*\"(installed|installing|restoring)\"", RegexOptions.IgnoreCase);
    }

    private static bool CanRemovePrevious(string folder) {
        if (!File.Exists(Path.Combine(folder, Marker)) || !File.Exists(Path.Combine(folder, FileList))) return false;
        var expected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in File.ReadAllLines(Path.Combine(folder, FileList), Encoding.UTF8)) {
            string[] parts = line.Split('|');
            if (parts.Length != 2) return false;
            string path = Payload.SafePath(folder, parts[0]);
            if (!File.Exists(path) || !Payload.Hash(path).Equals(parts[1], StringComparison.OrdinalIgnoreCase)) return false;
            expected.Add(path);
        }
        foreach (string name in new [] {Marker, FileList, "Uninstall.exe"}) expected.Add(Path.Combine(folder, name));
        foreach (string path in Directory.GetFiles(folder, "*", SearchOption.AllDirectories)) {
            if (!expected.Contains(path)) return false;
        }
        return true;
    }

    internal static string Install(bool desktop, Action<int,string> progress) {
        string parent = Path.GetDirectoryName(InstallRoot);
        Directory.CreateDirectory(parent);
        bool upgrading = Directory.Exists(InstallRoot);
        if (upgrading && !File.Exists(Path.Combine(InstallRoot, Marker)))
            throw new IOException("مجلد التطبيق موجود، لكنه ليس تابعًا لهذا المثبّت. لم نغيّره.");
        if (upgrading && Process.GetProcessesByName("HytaleArabicManager").Length > 0)
            throw new IOException("أغلق تطبيق التعريب قبل تحديثه.");
        string stage = Path.Combine(parent, "HytaleArabicManager.stage-" + Guid.NewGuid().ToString("N"));
        string previous = null;
        Directory.CreateDirectory(stage);
        try {
            Payload.Extract(stage, progress);
            File.WriteAllText(Path.Combine(stage, Marker), AppVersion, Encoding.UTF8);
            File.Copy(Assembly.GetExecutingAssembly().Location, Path.Combine(stage, "Uninstall.exe"));
            if (upgrading) {
                previous = Path.Combine(parent, "HytaleArabicManager.previous-" + Guid.NewGuid().ToString("N"));
                Directory.Move(InstallRoot, previous);
            }
            try { Directory.Move(stage, InstallRoot); }
            catch {
                if (previous != null && Directory.Exists(previous) && !Directory.Exists(InstallRoot))
                    Directory.Move(previous, InstallRoot);
                throw;
            }
        } catch {
            if (Directory.Exists(stage)) Directory.Delete(stage, true);
            throw;
        }
        string manager = Path.Combine(InstallRoot, "HytaleArabicManager.exe");
        string warning = "";
        if (previous != null) {
            try {
                if (CanRemovePrevious(previous)) Directory.Delete(previous, true);
                else warning = "حُفظت النسخة السابقة في " + previous;
            } catch { warning = "حُفظت النسخة السابقة في " + previous; }
        }
        try {
            MakeShortcut(StartShortcut, manager);
            if (desktop) MakeShortcut(DesktopShortcut, manager);
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(UninstallKey)) {
                key.SetValue("DisplayName", AppName);
                key.SetValue("DisplayVersion", AppVersion);
                key.SetValue("Publisher", "Hytale Arabic localization project");
                key.SetValue("InstallLocation", InstallRoot);
                key.SetValue("DisplayIcon", manager);
                key.SetValue("UninstallString", "\"" + Path.Combine(InstallRoot, "Uninstall.exe") + "\" --uninstall");
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        } catch (Exception ex) { warning += " تعذّر إنشاء أحد الاختصارات أو إدخال الإزالة: " + ex.Message; }
        progress(100, "اكتمل تثبيت التطبيق");
        return warning;
    }

    internal static string Uninstall() {
        if (!File.Exists(Path.Combine(InstallRoot, Marker))) throw new IOException("لم نجد نسخة مثبّتة بهذا التطبيق.");
        if (GameTranslationInstalled()) throw new IOException("التعريب مركّب داخل اللعبة. افتح التطبيق وأعد ملفات اللعبة الأصلية قبل إزالة التطبيق.");
        if (Process.GetProcessesByName("HytaleArabicManager").Length > 0) throw new IOException("أغلق تطبيق التعريب ثم حاول إزالة التطبيق.");
        string manifest = Path.Combine(InstallRoot, FileList);
        if (!File.Exists(manifest)) throw new IOException("قائمة ملفات التطبيق مفقودة؛ توقفنا حمايةً للملفات الأخرى.");
        var tracked = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in File.ReadAllLines(manifest, Encoding.UTF8)) {
            string[] parts = line.Split('|');
            if (parts.Length != 2) throw new IOException("قائمة الملفات غير صالحة.");
            string path = Payload.SafePath(InstallRoot, parts[0]);
            tracked.Add(path);
            if (File.Exists(path)) {
                string hash = Payload.Hash(path);
                if (!hash.Equals(parts[1], StringComparison.OrdinalIgnoreCase))
                    throw new IOException("تغيّر أحد ملفات التطبيق؛ أوقفنا الإزالة حمايةً لتعديلاتك: " + parts[0]);
            }
        }
        string packageRoot = Path.Combine(InstallRoot, "package");
        bool preservePackage = false;
        foreach (string file in Directory.GetFiles(InstallRoot, "*", SearchOption.AllDirectories)) {
            if (tracked.Contains(file) || file == manifest || file == Path.Combine(InstallRoot, Marker) || file == Path.Combine(InstallRoot, "Uninstall.exe")) continue;
            if (!file.StartsWith(packageRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                throw new IOException("وجدنا ملفًا أضيف إلى مجلد التطبيق؛ توقفنا حتى لا نفقده: " + file);
            preservePackage = true;
        }
        string savedPackage = null;
        if (preservePackage) {
            savedPackage = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HytaleArabicManagerSavedPackage-" + Guid.NewGuid().ToString("N"));
            Directory.Move(packageRoot, savedPackage);
        }
        foreach (string line in File.ReadAllLines(manifest, Encoding.UTF8)) {
            string path = Payload.SafePath(InstallRoot, line.Split('|')[0]);
            if (File.Exists(path)) File.Delete(path);
        }
        foreach (string owned in new [] {Marker, FileList, "Uninstall.exe"}) {
            string path = Path.Combine(InstallRoot, owned);
            if (File.Exists(path)) File.Delete(path);
        }
        string[] folders = Directory.GetDirectories(InstallRoot, "*", SearchOption.AllDirectories);
        Array.Sort(folders, (a,b) => b.Length.CompareTo(a.Length));
        foreach (string folder in folders) if (Directory.GetFileSystemEntries(folder).Length == 0) Directory.Delete(folder);
        if (Directory.GetFileSystemEntries(InstallRoot).Length == 0) Directory.Delete(InstallRoot);
        if (File.Exists(StartShortcut)) File.Delete(StartShortcut);
        if (File.Exists(DesktopShortcut)) File.Delete(DesktopShortcut);
        Registry.CurrentUser.DeleteSubKey(UninstallKey, false);
        return savedPackage == null ? "" : "حُفظت حزمة التعريب المحلية في " + savedPackage;
    }
}

internal static class Payload {
    private static Dictionary<string,string> Expected() {
        var expected = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("HytaleArabic.Manifest")) {
            if (resource == null) throw new IOException("قائمة ملفات التطبيق غير موجودة.");
            using (var reader = new StreamReader(resource, Encoding.UTF8)) {
                string line;
                while ((line = reader.ReadLine()) != null) {
                    string[] parts = line.Split('|');
                    if (parts.Length != 2 || !Regex.IsMatch(parts[1], "^[0-9A-Fa-f]{64}$") || expected.ContainsKey(parts[0]))
                        throw new IOException("قائمة الملفات غير صالحة.");
                    expected.Add(parts[0], parts[1]);
                }
            }
        }
        if (expected.Count < 20) throw new IOException("حزمة التطبيق غير مكتملة.");
        return expected;
    }

    internal static string SafePath(string root, string relative) {
        if (String.IsNullOrWhiteSpace(relative) || relative.StartsWith("/") || relative.StartsWith("\\") ||
            relative.Contains(":") || relative.Contains("..") || relative.Contains("\\"))
            throw new IOException("مسار غير صالح داخل الحزمة.");
        string full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase)) throw new IOException("مسار خارج مجلد التثبيت.");
        return full;
    }

    internal static string Hash(string path) {
        using (var sha = SHA256.Create())
        using (var stream = File.OpenRead(path)) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }

    internal static void Extract(string destination, Action<int,string> progress) {
        Dictionary<string,string> expected = Expected();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("HytaleArabic.Payload")) {
            if (stream == null) throw new IOException("ملفات التطبيق غير موجودة.");
            using (var zip = new ZipArchive(stream, ZipArchiveMode.Read)) {
                if (zip.Entries.Count != expected.Count) throw new IOException("عدد ملفات الحزمة لا يطابق قائمتها.");
                int count = 0;
                foreach (ZipArchiveEntry entry in zip.Entries) {
                    string hash;
                    if (!expected.TryGetValue(entry.FullName, out hash) || !seen.Add(entry.FullName))
                        throw new IOException("ملف غير متوقع داخل الحزمة.");
                    string target = SafePath(destination, entry.FullName);
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    using (Stream input = entry.Open())
                    using (Stream output = File.Create(target)) input.CopyTo(output);
                    if (!Hash(target).Equals(hash, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("تعذّر التحقق من الملف: " + entry.FullName);
                    count++;
                    if (progress != null) progress(Math.Min(98, (int)Math.Round(count * 98.0 / expected.Count)), "نجهّز ملفات التطبيق " + count + " / " + expected.Count);
                }
            }
        }
        using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("HytaleArabic.Manifest"))
        using (Stream target = File.Create(Path.Combine(destination, SetupProgram.FileList))) source.CopyTo(target);
    }
}

internal sealed class SetupWindow : Form {
    private readonly bool removing;
    private readonly Label state = new Label();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Button action = new Button();
    private readonly CheckBox desktop = new CheckBox();
    private bool busy;
    private bool completed;

    internal SetupWindow(bool remove) {
        removing = remove;
        Text = remove ? "إزالة تعريب هايتل" : "تثبيت تعريب هايتل";
        ClientSize = new Size(660, 400);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        RightToLeft = RightToLeft.Yes;
        BackColor = Color.FromArgb(14,27,43);
        ForeColor = Color.FromArgb(232,242,250);
        Font = new Font("Tahoma", 9.5f);
        var panel = new Panel {Left=0,Top=0,Width=660,Height=100,BackColor=Color.FromArgb(23,42,62)};
        Controls.Add(panel);
        AddLabel(panel, "H", 579,24,48,49,28,Color.FromArgb(218,181,104),true);
        AddLabel(panel, remove ? "إزالة التطبيق" : "تعريب هايتل", 245,23,320,43,20,ForeColor,true);
        AddLabel(panel, "تعريب اللعبة 0.7.0  •  التطبيق " + SetupProgram.AppVersion, 255,63,310,24,9,Color.FromArgb(154,177,195),false);
        var line = new Panel {Left=0,Top=97,Width=660,Height=3,BackColor=Color.FromArgb(218,181,104)};
        panel.Controls.Add(line);
        AddLabel(this, remove ? "إزالة التطبيق من هذا الجهاز" : "كل ما تحتاجه في ملف تثبيت واحد", 36,120,588,36,14,ForeColor,true);
        AddLabel(this, remove ? "لن تُمسّ ملفات اللعبة. أعد التعريب من داخل التطبيق أولًا إن كان مركّبًا." :
            "سيُضاف التطبيق إلى قائمة ابدأ والتطبيقات المثبّتة. لن تُغيَّر ملفات اللعبة أثناء تثبيت التطبيق.",
            36,160,588,48,9,Color.FromArgb(154,177,195),false);
        if (!remove) {
            desktop.Text = "إضافة اختصار إلى سطح المكتب";
            desktop.Checked = true;
            desktop.SetBounds(305,212,319,28);
            desktop.ForeColor = ForeColor;
            desktop.RightToLeft = RightToLeft.Yes;
            Controls.Add(desktop);
        }
        progress.SetBounds(36,261,588,14);
        progress.RightToLeft = RightToLeft.Yes;
        progress.RightToLeftLayout = true;
        progress.Style = ProgressBarStyle.Continuous;
        Controls.Add(progress);
        state.SetBounds(36,284,588,27);
        state.RightToLeft = RightToLeft.Yes;
        state.TextAlign = ContentAlignment.MiddleLeft;
        state.Text = remove ? "جاهز للإزالة" : "جاهز للتثبيت";
        state.ForeColor = Color.FromArgb(154,177,195);
        Controls.Add(state);
        action.SetBounds(36,329,588,48);
        string installedMarker = Path.Combine(SetupProgram.InstallRoot, SetupProgram.Marker);
        bool installed = File.Exists(installedMarker);
        bool sameVersion = installed && File.ReadAllText(installedMarker, Encoding.UTF8).Trim() == SetupProgram.AppVersion;
        action.Text = remove ? "إزالة التطبيق" : sameVersion ? "فتح التطبيق" : installed ? "تحديث التطبيق" : "تثبيت التطبيق";
        action.BackColor = Color.FromArgb(218,181,104);
        action.ForeColor = Color.FromArgb(14,27,43);
        action.FlatStyle = FlatStyle.Flat;
        action.FlatAppearance.BorderSize = 0;
        action.Font = new Font("Tahoma", 11, FontStyle.Bold);
        action.Click += (s,e) => Begin();
        Controls.Add(action);
        FormClosing += (s,e) => {if (busy) {e.Cancel=true;state.Text="انتظر حتى يكتمل العمل.";}};
    }

    private static void AddLabel(Control parent,string text,int x,int y,int w,int h,float size,Color color,bool bold) {
        var label = new Label {Text=text,Left=x,Top=y,Width=w,Height=h,ForeColor=color,
            RightToLeft=RightToLeft.Yes,TextAlign=ContentAlignment.MiddleLeft,
            Font=new Font("Tahoma",size,bold?FontStyle.Bold:FontStyle.Regular)};
        parent.Controls.Add(label);
    }

    private void Begin() {
        if (busy) return;
        if (completed) {
            if (!removing) {
                string installedManager = Path.Combine(SetupProgram.InstallRoot, "HytaleArabicManager.exe");
                if (File.Exists(installedManager)) Process.Start(installedManager);
            }
            Close();
            return;
        }
        string installedMarker = Path.Combine(SetupProgram.InstallRoot, SetupProgram.Marker);
        if (!removing && File.Exists(installedMarker) && File.ReadAllText(installedMarker, Encoding.UTF8).Trim() == SetupProgram.AppVersion) {
            string manager = Path.Combine(SetupProgram.InstallRoot, "HytaleArabicManager.exe");
            if (File.Exists(manager)) Process.Start(manager);
            Close();
            return;
        }
        if (removing && SetupProgram.GameTranslationInstalled()) {
            MessageBox.Show("التعريب مركّب داخل اللعبة. افتح تطبيق التعريب واسترجع ملفات اللعبة الأصلية، ثم أزل التطبيق.",
                SetupProgram.AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        busy=true;
        action.Enabled=false;
        desktop.Enabled=false;
        state.Text=removing?"نزيل التطبيق...":"نجهّز التطبيق...";
        bool addDesktop=desktop.Checked;
        var worker = new BackgroundWorker {WorkerReportsProgress=true};
        worker.DoWork += (s,e) => {
            if (removing) e.Result=SetupProgram.Uninstall();
            else e.Result=SetupProgram.Install(addDesktop, (percent,message) => worker.ReportProgress(percent,message));
        };
        worker.ProgressChanged += (s,e) => {progress.Value=Math.Max(0,Math.Min(100,e.ProgressPercentage));state.Text=(string)e.UserState;};
        worker.RunWorkerCompleted += (s,e) => {
            busy=false;
            if (e.Error != null) {
                state.Text="لم يكتمل العمل";
                MessageBox.Show(e.Error.Message,SetupProgram.AppName,MessageBoxButtons.OK,MessageBoxIcon.Error);
                action.Enabled=true;desktop.Enabled=true;
                return;
            }
            progress.Value=100;
            state.Text=removing?"اكتملت إزالة التطبيق":"اكتمل تثبيت التطبيق";
            if (e.Result is string && ((string)e.Result).Length>0) MessageBox.Show((string)e.Result,SetupProgram.AppName);
            action.Text=removing?"إغلاق":"فتح التطبيق";
            action.Enabled=true;
            completed=true;
        };
        worker.RunWorkerAsync();
    }
}
