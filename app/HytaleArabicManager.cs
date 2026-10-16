using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class Program {
    [STAThread] private static void Main() {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new ManagerWindow());
    }
}

internal sealed class ProgressTrack : Control {
    public int Percent { get; set; }
    public bool Busy { get; set; }
    public int Tick { get; set; }
    public ProgressTrack() { DoubleBuffered=true; Height=12; RightToLeft=RightToLeft.Yes; }
    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        var track=new Rectangle(0,0,Math.Max(1,Width-1),Math.Max(1,Height-1));
        using(var bg=new SolidBrush(Color.FromArgb(37,57,77))) e.Graphics.FillRectangle(bg,track);
        if(Busy) {
            int width=Math.Max(28,Width/5);
            int left=Width-(Tick%(Width+width));
            using(var brush=new SolidBrush(Color.FromArgb(218,181,104))) e.Graphics.FillRectangle(brush,left,0,width,Height);
        } else if(Percent>0) {
            int width=(int)Math.Round(Width*Math.Min(100,Percent)/100.0);
            using(var brush=new SolidBrush(Color.FromArgb(218,181,104))) e.Graphics.FillRectangle(brush,Width-width,0,width,Height);
        }
    }
}

internal sealed class ManagerWindow : Form {
    private sealed class RunResult { public int ExitCode; public string Output; public string Error; }
    private static readonly Color Base=Color.FromArgb(14,27,43);
    private static readonly Color Surface=Color.FromArgb(23,42,62);
    private static readonly Color Muted=Color.FromArgb(154,177,195);
    private static readonly Color Ice=Color.FromArgb(232,242,250);
    private static readonly Color Gold=Color.FromArgb(218,181,104);
    private static readonly Color Good=Color.FromArgb(131,203,176);
    private readonly string bundle=Path.GetDirectoryName(typeof(ManagerWindow).Assembly.Location);
    private readonly bool portable;
    private readonly TextBox root=new TextBox();
    private readonly TextBox details=new TextBox();
    private readonly Button apply=new Button();
    private readonly Button restore=new Button();
    private readonly Button choose=new Button();
    private readonly Button toggleDetails=new Button();
    private readonly Button updateButton=new Button();
    private readonly Label statusText=new Label();
    private readonly Label statusHelp=new Label();
    private Label progressText=new Label();
    private Label percent=new Label();
    private Label pathSummary=new Label();
    private Label footerHint=new Label();
    private Label applyHint=new Label();
    private Label restoreHint=new Label();
    private readonly ProgressTrack bar=new ProgressTrack();
    private readonly Timer animation=new Timer();
    private bool running;
    private bool checkingUpdate;
    private AvailableUpdate availableUpdate;
    private string currentAction="";
    private int lastDone, lastTotal;

    internal ManagerWindow() {
        portable=!File.Exists(Path.Combine(bundle,".hytale-arabic-managed"));
        Text="تعريب هايتل";
        ClientSize=new Size(800,565);
        MinimumSize=new Size(800,565);
        MaximumSize=new Size(800,565);
        FormBorderStyle=FormBorderStyle.FixedSingle;
        MaximizeBox=false;
        AutoScaleMode=AutoScaleMode.Dpi;
        BackColor=Base;
        ForeColor=Ice;
        RightToLeft=RightToLeft.Yes;
        Font=new Font("Tahoma",9.5f);
        StartPosition=FormStartPosition.CenterScreen;
        BuildHeader();
        BuildStatus();
        BuildLocation();
        BuildActions();
        BuildProgress();
        animation.Interval=35;
        animation.Tick+=(s,e)=>{if(bar.Busy){bar.Tick+=7;bar.Invalidate();}};
        FormClosing+=(s,e)=>{
            if(running){e.Cancel=true;statusHelp.Text="انتظر حتى يكتمل العمل لحماية ملفات اللعبة.";}
        };
        Shown+=(s,e)=>Run("status");
    }

    private Label Label(string text, int x,int y,int w,int h, float size, Color color, bool bold=false) {
        var label=new Label{Text=text,Left=x,Top=y,Width=w,Height=h,ForeColor=color,
            Font=new Font("Tahoma",size,bold?FontStyle.Bold:FontStyle.Regular),
            TextAlign=ContentAlignment.MiddleLeft,RightToLeft=RightToLeft.Yes};
        Controls.Add(label);
        return label;
    }
    private void BuildHeader() {
        var header=new Panel{Left=0,Top=0,Width=800,Height=110,BackColor=Surface};
        Controls.Add(header);
        var emblem=new Label{Text="H",Left=724,Top=28,Width=45,Height=48,
            Font=new Font("Georgia",30,FontStyle.Bold),ForeColor=Gold,TextAlign=ContentAlignment.MiddleCenter};
        header.Controls.Add(emblem);
        var title=new Label{Text="تعريب هايتل",Left=340,Top=20,Width=360,Height=49,
            Font=new Font("Tahoma",22,FontStyle.Bold),ForeColor=Ice,TextAlign=ContentAlignment.MiddleLeft,RightToLeft=RightToLeft.Yes};
        header.Controls.Add(title);
        var subtitle=new Label{Text="النسخة المحلية",Left=560,Top=69,Width=140,Height=22,
            Font=new Font("Tahoma",9),ForeColor=Muted,TextAlign=ContentAlignment.MiddleLeft,RightToLeft=RightToLeft.Yes};
        header.Controls.Add(subtitle);
        var version=new Label{Text="0.7.0",Left=510,Top=69,Width=48,Height=22,
            Font=new Font("Tahoma",9),ForeColor=Muted,TextAlign=ContentAlignment.MiddleLeft,RightToLeft=RightToLeft.No};
        header.Controls.Add(version);
        updateButton.Text="فحص تحديث التطبيق";
        updateButton.SetBounds(31,66,230,31);
        StyleButton(updateButton,Surface,Ice,false);
        updateButton.Click+=(s,e)=>{
            if(running || checkingUpdate)return;
            if(availableUpdate==null)CheckForUpdates(); else DownloadUpdate();
        };
        header.Controls.Add(updateButton);
        var edge=new Panel{Left=0,Top=107,Width=800,Height=3,BackColor=Gold};
        header.Controls.Add(edge);
    }
    private void BuildStatus() {
        var box=new Panel{Left=31,Top=129,Width=738,Height=85,BackColor=Surface};
        Controls.Add(box);
        var badge=new Label{Text="●",Left=689,Top=17,Width=30,Height=30,ForeColor=Gold,
            Font=new Font("Tahoma",17),TextAlign=ContentAlignment.MiddleCenter};
        box.Controls.Add(badge);
        statusText.Text="نفحص حالة التعريب...";
        statusText.SetBounds(44,14,625,28);
        statusText.Font=new Font("Tahoma",12,FontStyle.Bold);
        statusText.ForeColor=Ice;
        statusText.TextAlign=ContentAlignment.MiddleLeft;
        statusText.RightToLeft=RightToLeft.Yes;
        box.Controls.Add(statusText);
        statusHelp.Text="سيحدد التطبيق الخطوة المناسبة.";
        statusHelp.SetBounds(44,47,625,22);
        statusHelp.ForeColor=Muted;
        statusHelp.TextAlign=ContentAlignment.MiddleLeft;
        statusHelp.RightToLeft=RightToLeft.Yes;
        box.Controls.Add(statusHelp);
    }
    private void BuildLocation() {
        pathSummary=Label("وجدنا مجلد اللعبة تلقائيًا",31,244,574,32,9,Muted);
        root.Left=31;root.Top=278;root.Width=574;root.Height=28;
        root.RightToLeft=RightToLeft.No;
        root.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Hytale");
        root.BackColor=Surface;root.ForeColor=Ice;root.BorderStyle=BorderStyle.FixedSingle;
        root.Visible=false;
        Controls.Add(root);
        pathSummary.Text=Directory.Exists(root.Text)?"تم العثور على اللعبة تلقائيًا":"لم نعثر على اللعبة، اختر مجلدها";
        new ToolTip().SetToolTip(pathSummary,root.Text);
        choose.Text="تغيير مكان اللعبة";choose.SetBounds(622,244,147,32);
        StyleButton(choose,Surface,Ice,false);
        choose.Click+=(s,e)=>{
            using(var picker=new FolderBrowserDialog()){
                picker.SelectedPath=root.Text;
                picker.Description="اختر مجلد Hytale الذي يحتوي install وUserData";
                if(picker.ShowDialog(this)==DialogResult.OK){root.Text=picker.SelectedPath;pathSummary.Text="تم اختيار مجلد اللعبة";Run("status");}
            }
        };
        Controls.Add(choose);
    }
    private void BuildActions() {
        apply.Text="تثبيت التعريب"; apply.SetBounds(31,306,738,55);
        StyleButton(apply,Gold,Base,true);
        apply.Click+=(s,e)=>Run("install");
        Controls.Add(apply);
        restore.Text="تجهيز اللعبة للتحديث";restore.SetBounds(31,306,738,55);
        StyleButton(restore,Gold,Base,true);
        restore.Click+=(s,e)=>Run("restore");
        Controls.Add(restore);
        applyHint=Label("بعدها افتح اللعبة من مشغّلها المعتاد",31,365,738,23,8.5f,Muted);
        restoreHint=Label("يعيد الملفات الأصلية قبل تحديث اللعبة",31,365,738,23,8.5f,Muted);
        apply.Visible=false;restore.Visible=false;applyHint.Visible=false;restoreHint.Visible=false;
    }
    private void SetNextAction(bool needsRestore) {
        apply.Visible=!needsRestore;
        applyHint.Visible=!needsRestore;
        restore.Visible=needsRestore;
        restoreHint.Visible=needsRestore;
        apply.Enabled=!needsRestore;
        restore.Enabled=needsRestore;
    }
    private void BuildProgress() {
        progressText=Label("جاهز",270,410,499,25,9.5f,Ice,true);
        percent=Label("",31,410,220,25,9.5f,Gold,true);
        percent.RightToLeft=RightToLeft.No;
        percent.TextAlign=ContentAlignment.MiddleLeft;
        bar.SetBounds(31,446,738,13);
        bar.Visible=false;
        Controls.Add(bar);
        toggleDetails.Text="عرض التفاصيل";toggleDetails.SetBounds(637,484,132,27);
        StyleButton(toggleDetails,Base,Muted,false);
        toggleDetails.Click+=(s,e)=>{
            details.Visible=!details.Visible;
            toggleDetails.Text=details.Visible?"إخفاء التفاصيل":"عرض التفاصيل";
        };
        Controls.Add(toggleDetails);
        footerHint=Label("اختر الخطوة المناسبة ثم اتبع الرسالة الظاهرة",31,484,590,27,8.5f,Muted);
        details.SetBounds(31,517,738,39);
        details.ReadOnly=true;details.Multiline=true;details.ScrollBars=ScrollBars.Vertical;
        details.RightToLeft=RightToLeft.No;details.BackColor=Surface;details.ForeColor=Muted;
        details.BorderStyle=BorderStyle.None;details.Visible=false;
        Controls.Add(details);
    }
    private void StyleButton(Button button,Color back,Color fore,bool strong) {
        button.FlatStyle=FlatStyle.Flat;
        button.FlatAppearance.BorderSize=strong?0:1;
        button.FlatAppearance.BorderColor=Color.FromArgb(66,91,111);
        button.BackColor=back;button.ForeColor=fore;
        button.Font=new Font("Tahoma",strong?11:9,strong?FontStyle.Bold:FontStyle.Regular);
        button.Cursor=Cursors.Hand;
        button.UseVisualStyleBackColor=false;
    }
    private static string Quote(string text) {
        if(text.IndexOfAny(new []{'"','\r','\n'})>=0) throw new ArgumentException("المسار الذي اخترته غير صالح.");
        return "\""+text+"\"";
    }
    private static bool IsHytaleOpen() {
        foreach(string name in new []{"HytaleClient","HytaleLauncher","hytale-launcher"})
            if(Process.GetProcessesByName(name).Length>0)return true;
        return false;
    }
    private string StageText(string stage) {
        switch(stage){
            case "version": return "نتأكد من نسخة اللعبة";
            case "fonts": return "نجهّز الخط العربي من ملفات اللعبة";
            case "world": return "نجهّز نصوص العالم";
            case "loading": return "نجهّز شاشات اللعبة";
            case "check": return "نفحص الملفات";
            case "backup": return "نحفظ الملفات الأصلية";
            case "apply": return "نضع التعريب";
            case "verify": return "نتأكد من النتيجة";
            case "restore": return "نعيد ملفات اللعبة الأصلية";
            default: return "نعمل على طلبك";
        }
    }
    private void Run(string action) {
        if(running) return;
        if(action!="status" && IsHytaleOpen()) {
            MessageBox.Show(this,"أغلق لعبة هايتل ومشغّلها تمامًا، ثم اضغط الزر مرة أخرى.",
                "إغلاق اللعبة والمشغّل",MessageBoxButtons.OK,MessageBoxIcon.Information);
            return;
        }
        string game,script,package;
        try {
            game=Path.GetFullPath(root.Text.Trim());
            script=Path.Combine(bundle,"tools","ManagePackage.ps1");
            package=Path.Combine(bundle,"package");
            if(!Directory.Exists(game)) throw new DirectoryNotFoundException("لم نجد مجلد اللعبة. اضغط تغيير واختر مجلد Hytale.");
            if(!File.Exists(script))
                throw new FileNotFoundException("ملفات التطبيق ناقصة. افتحه من مجلده الكامل.");
        } catch(Exception problem) { ShowError(problem.Message);return; }
        running=true;currentAction=action;lastDone=0;lastTotal=0;details.Clear();
        apply.Enabled=false;restore.Enabled=false;choose.Enabled=false;root.Enabled=false;updateButton.Enabled=false;
        bar.Visible=(action!="status");
        bar.Busy=(action!="status");bar.Percent=0;bar.Tick=0;bar.Invalidate();
        if(action!="status") animation.Start();
        percent.Text="";
        progressText.Text=action=="install"?"نبدأ تطبيق التعريب...":action=="restore"?"نبدأ استرجاع ملفات اللعبة...":"نفحص الحالة...";
        footerHint.Text="اترك التطبيق مفتوحًا حتى ينتهي العمل";
        statusText.Text="العمل جارٍ...";
        statusHelp.Text="اترك التطبيق مفتوحًا حتى تظهر النتيجة.";
        var worker=new BackgroundWorker();
        worker.DoWork+=(s,e)=>{
            var info=new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -File "+Quote(script)+" -Action "+action+
                " -GameRoot "+Quote(game)+" -PackageRoot "+Quote(package));
            info.UseShellExecute=false;info.CreateNoWindow=true;
            info.RedirectStandardOutput=true;info.RedirectStandardError=true;
            info.StandardOutputEncoding=Encoding.UTF8;info.StandardErrorEncoding=Encoding.UTF8;
            var stdout=new StringBuilder();
            var stderr=new StringBuilder();
            using(var process=new Process()){
                process.StartInfo=info;
                process.OutputDataReceived+=(sender,args)=>{if(args.Data!=null){stdout.AppendLine(args.Data);ReceiveLine(args.Data,false);}};
                process.ErrorDataReceived+=(sender,args)=>{if(args.Data!=null){stderr.AppendLine(args.Data);ReceiveLine(args.Data,true);}};
                process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();
                process.WaitForExit();
                e.Result=new RunResult{ExitCode=process.ExitCode,Output=stdout.ToString(),Error=stderr.ToString()};
            }
        };
        worker.RunWorkerCompleted+=(s,e)=>{
            try {
            animation.Stop();bar.Busy=false;
            apply.Enabled=true;restore.Enabled=true;choose.Enabled=true;root.Enabled=true;updateButton.Enabled=true;
            if(e.Error!=null){ShowError(e.Error.Message);return;}
            var result=(RunResult)e.Result;
            if(result.ExitCode!=0){
                ShowError(FriendlyError(result.Error));return;
            }
            if(action!="status"){bar.Percent=100;bar.Invalidate();percent.Text="100%";}
            if(action=="install") {
                statusText.Text="اكتمل تطبيق التعريب";
                statusHelp.Text="افتح اللعبة من مشغّل هايتل المعتاد لتجربته.";
                progressText.Text="اكتمل التثبيت والفحص";
                SetNextAction(true);
                footerHint.Text="أغلق التطبيق أو افتح اللعبة من مشغّلها";
            } else if(action=="restore") {
                if(result.Output.Contains("LegacyTooltip: modified"))ShowLegacyTooltipWarning();
                else {
                    statusText.Text="اللعبة جاهزة للتحديث";
                    statusHelp.Text="افتح مشغّل هايتل المعتاد وحدّث اللعبة.";
                    progressText.Text="عادت الملفات الأصلية";
                    SetNextAction(false);
                    footerHint.Text="أغلق التطبيق ثم حدّث اللعبة من مشغّلها";
                }
            } else {
                UpdateStatus(result.Output);
                progressText.Text="اختر ما تريد فعله";
                footerHint.Text="اختر الخطوة المناسبة ثم اتبع الرسالة الظاهرة";
            }
            } finally {running=false;if(action=="status")CheckForUpdates();}
        };
        worker.RunWorkerAsync();
    }
    private void ReceiveLine(string line,bool error) {
        if(IsDisposed||!IsHandleCreated) return;
        try { BeginInvoke((Action)(()=>{
            if(line.StartsWith("PROGRESS|")) {
                var parts=line.Split('|');
                int done,total;
                if(parts.Length>=5 && int.TryParse(parts[2],out done) && int.TryParse(parts[3],out total) && total>0){
                    lastDone=done;lastTotal=total;
                    bar.Busy=(done==0);bar.Percent=Math.Max(0,Math.Min(100,(int)Math.Round(done*100.0/total)));
                    bar.Invalidate();
                    progressText.Text=StageText(parts[4]);
                    percent.Text=done==0?"":done+" / "+total+"  •  "+bar.Percent+"%";
                }
                return;
            }
            if(line.Trim().Length>0)details.AppendText(line+Environment.NewLine);
        })); } catch(InvalidOperationException) {}
    }
    private void UpdateStatus(string text) {
        if(text.Contains("Localization: installed")){
            statusText.Text="التعريب مثبّت";
            statusHelp.Text="إذا أردت تحديث اللعبة، أعد الملفات الأصلية أولًا.";
            SetNextAction(true);
        } else if(text.Contains("Localization: installing")||text.Contains("Localization: restoring")){
            statusText.Text="يحتاج التعريب إلى استرجاع";
            statusHelp.Text="اضغط «تجهيز اللعبة للتحديث» لإكمال الاسترجاع.";
            SetNextAction(true);
        } else if(text.Contains("LegacyTooltip: modified")){
            ShowLegacyTooltipWarning();
        } else {
            statusText.Text="اللعبة بملفاتها الأصلية";
            statusHelp.Text="يمكنك تشغيل التعريب إذا أردت تجربته.";
            SetNextAction(false);
        }
    }
    private void ShowLegacyTooltipWarning() {
        statusText.Text="بقي ملف وصف العناصر معدّلًا";
        statusHelp.Text="افتح إعدادات مشغّل هايتل واختر التحقق من ملفات اللعبة قبل التحديث.";
        progressText.Text="يحتاج ملف قديم إلى استرجاع";
        footerHint.Text="لن نعدّ اللعبة جاهزة للتحديث حتى يعود هذا الملف";
        apply.Visible=false;applyHint.Visible=false;restore.Visible=false;restoreHint.Visible=false;
    }
    private static string FriendlyError(string raw) {
        if(raw.Contains("Game version changed")||raw.Contains("package identity")) return "نسخة اللعبة تغيّرت؛ تحتاج حزمة تعريب تناسب هذا التحديث. لم نركّب ملفات قديمة.";
        if(raw.Contains("File validation failed")||raw.Contains("Changed game file")) return "ملفات اللعبة تغيّرت. توقفنا حتى لا نستبدل ملفات غير متوقعة. التفاصيل بالأسفل.";
        if(raw.Contains("Assert-Closed")||raw.Contains("أغلق اللعبة")) return "أغلق اللعبة والمشغّل، ثم أعد المحاولة.";
        if(raw.Contains("backup")||raw.Contains("Backup")) return "تعذر التأكد من النسخة الأصلية. توقفنا لحماية ملفات اللعبة.";
        return "توقف العمل لحماية ملفات اللعبة. افتح التفاصيل لمعرفة السبب.";
    }
    private void ShowError(string message) {
        animation.Stop();bar.Busy=false;bar.Invalidate();
        statusText.Text="لم يكتمل العمل";
        statusHelp.Text=message;
        progressText.Text="لم تتغير حالة التطبيق إلى مكتمل";
        footerHint.Text="يمكنك فتح التفاصيل لمعرفة السبب";
        if(currentAction=="install" && details.Text.Contains("Installation interrupted"))SetNextAction(true);
        if(details.Text.Length==0)details.Text=message;
    }

    private void CheckForUpdates() {
        if(checkingUpdate || running)return;
        checkingUpdate=true;
        updateButton.Enabled=false;
        updateButton.Text="نفحص التحديثات...";
        updateButton.BackColor=Surface;updateButton.ForeColor=Ice;
        var worker=new BackgroundWorker();
        worker.DoWork+=(s,e)=>e.Result=GitHubUpdater.Check(portable);
        worker.RunWorkerCompleted+=(s,e)=>{
            checkingUpdate=false;
            updateButton.Enabled=!running;
            if(e.Error!=null){updateButton.Text="إعادة فحص التحديثات";return;}
            availableUpdate=(AvailableUpdate)e.Result;
            updateButton.Text=availableUpdate==null?"التطبيق محدّث · إعادة الفحص":"تحديث التطبيق إلى "+availableUpdate.Version;
            if(availableUpdate!=null){updateButton.BackColor=Gold;updateButton.ForeColor=Base;}
        };
        worker.RunWorkerAsync();
    }

    private void DownloadUpdate() {
        if(running || availableUpdate==null)return;
        running=true;
        apply.Enabled=false;restore.Enabled=false;choose.Enabled=false;updateButton.Enabled=false;
        bar.Visible=true;bar.Busy=false;bar.Percent=0;bar.Invalidate();
        percent.Text="0%";
        progressText.Text="ننزل تحديث التطبيق من GitHub";
        footerHint.Text="اترك التطبيق مفتوحًا حتى نتحقق من التحديث";
        var selected=availableUpdate;
        var worker=new BackgroundWorker{WorkerReportsProgress=true};
        worker.DoWork+=(s,e)=>{
            string file=GitHubUpdater.Download(selected,p=>worker.ReportProgress(portable?p*90/100:p));
            if(portable){
                worker.ReportProgress(95);
                e.Result=GitHubUpdater.ExtractPortable(file,selected.Version);
            } else e.Result=file;
        };
        worker.ProgressChanged+=(s,e)=>{
            bar.Percent=Math.Max(0,Math.Min(100,e.ProgressPercentage));bar.Invalidate();
            percent.Text=bar.Percent+"%";
            if(portable && bar.Percent>=95 && bar.Percent<100)progressText.Text="نجهّز النسخة المحمولة";
            if(bar.Percent==100)progressText.Text="اكتمل تنزيل التحديث والتحقق منه";
        };
        worker.RunWorkerCompleted+=(s,e)=>{
            if(e.Error!=null){
                running=false;apply.Enabled=true;restore.Enabled=true;choose.Enabled=true;updateButton.Enabled=true;
                progressText.Text="تعذّر تحديث التطبيق";
                footerHint.Text="أعد المحاولة أو افتح التفاصيل لمعرفة السبب";
                details.Text=e.Error.Message;
                return;
            }
            try {
                var start=new ProcessStartInfo((string)e.Result){UseShellExecute=true};
                if(!portable) start.Arguments="--wait-pid "+Process.GetCurrentProcess().Id;
                Process.Start(start);
                running=false;
                Close();
            } catch(Exception problem) {
                running=false;apply.Enabled=true;restore.Enabled=true;choose.Enabled=true;updateButton.Enabled=true;
                progressText.Text="تعذّر فتح النسخة الجديدة";
                details.Text=problem.Message;
            }
        };
        worker.RunWorkerAsync();
    }
}
