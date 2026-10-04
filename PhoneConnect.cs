using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace PhoneConnect
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    public class MainForm : Form
    {
        // ---- paths ----
        string ScriptDir, Adb, Scrcpy, IconPath, ExePath, ConfigPath, RecordDir, ShotDir, QrLib;

        // ---- colors ----
        Color cBg=Color.FromArgb(30,30,38), cPanel=Color.FromArgb(42,42,54), cAccent=Color.FromArgb(88,166,255),
              cGreen=Color.FromArgb(63,185,80), cRed=Color.FromArgb(200,64,64), cText=Color.FromArgb(230,230,235),
              cMuted=Color.FromArgb(150,150,165);
        Color cErr=Color.FromArgb(240,95,95), cOk=Color.FromArgb(90,225,130), cWarn=Color.FromArgb(240,190,80), cInfo=Color.FromArgb(120,165,140);
        Font fUI, fSmall, fMono, fBig;

        // ---- controls ----
        Button btnModeUsb, btnModeCode, btnModeQr, btnCheckUpd, btnHelp, btnShortcut, btnUpdate;
        Label lblIp, lblPort, lblPcode, lblCodeHelp, lblUsbHelp, lblNoDevice, lblFps, statusBar, lblVer, lblQrHelp;
        TextBox txtIp, txtPort, txtCode, txtMaxFps, scrcpyLog;
        RichTextBox log;
        Button btnConnect, btnDisconnect, btnDevices, btnRestart, btnUsb, btnQrStart, btnQrStop;
        Button btnOnTop, btnHiRes, btnNoAudio, btnMaxFps, btnRecord, btnShot, btnOpenRec, btnOpenShot, btnStart;
        Panel qrPanel; WebBrowser qrWeb;

        // ---- state ----
        string usbSerial = null;
        string mode = "code";
        Process scrcpyProc = null; bool recording = false; string recordFile = null; bool stopping = false;
        System.Windows.Forms.Timer mirrorTimer, devTimer, qrTimer;
        string qrService = null, qrPassword = null; int qrTries = 0; bool qrBusy = false;
        string cfgIp = "192.168.18.2";

        static void Sleep(int ms) { System.Threading.Thread.Sleep(ms); }

        public MainForm()
        {
            ScriptDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            Adb = Path.Combine(ScriptDir, "adb.exe");
            Scrcpy = Path.Combine(ScriptDir, "scrcpy.exe");
            IconPath = Path.Combine(ScriptDir, "PhoneConnect.ico");
            ExePath = Application.ExecutablePath;
            ConfigPath = Path.Combine(ScriptDir, "phoneconnect.config.json");
            RecordDir = Path.Combine(ScriptDir, "recordings");
            ShotDir = Path.Combine(ScriptDir, "screenshots");
            QrLib = Path.Combine(ScriptDir, "qrcode.min.js");

            fUI = new Font("Segoe UI", 10f);
            fSmall = new Font("Segoe UI", 8.5f);
            fMono = new Font("Consolas", 9f);
            fBig = new Font("Segoe UI Semibold", 11f);

            LoadConfig();

            Text = "Phone Connect";
            ClientSize = new Size(534, 572);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = cBg; ForeColor = cText; Font = fUI;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            AutoScaleMode = AutoScaleMode.None;   // lock the fixed pixel layout (no DPI/font scaling distortion)
            try { if (File.Exists(IconPath)) Icon = new Icon(IconPath); } catch { }

            BuildUi();

            FormClosing += delegate {
                if (devTimer != null) devTimer.Stop();
                StopQrPolling(); StopWatch();
                SaveConfig(txtIp.Text.Trim(), txtPort.Text.Trim());
            };
            Load += delegate {
                SetMode("code");
                SetRecIndicator();
                AppendLog("Ready. Click \"How to use\" for a quick guide.", null);
                devTimer.Start();
                Task.Run((Action)delegate {
                    string v = GetLocalScrcpyVersion();
                    UI(delegate { lblVer.Text = v != null ? "scrcpy v" + v : "scrcpy"; });
                });
            };
        }

        // ---------- UI helpers ----------
        void UI(Action a) { try { if (InvokeRequired) BeginInvoke(a); else a(); } catch { } }

        Label MakeLabel(string t, int x, int y, int w, int h, Font f, Color? c, Control parent)
        {
            Label l = new Label();
            l.AutoSize = false; l.Text = t; l.Location = new Point(x, y); l.Size = new Size(w, h);
            if (f != null) l.Font = f; if (c.HasValue) l.ForeColor = c.Value;
            (parent ?? (Control)this).Controls.Add(l); return l;
        }
        void StyleButton(Button b, Color fill)
        {
            b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderSize = 0;
            b.BackColor = fill; b.ForeColor = Color.White; b.Font = fUI;   // no Cursors.Hand - keep the user's own cursor
            b.TextAlign = ContentAlignment.MiddleCenter;   // keep label centered at any size
            b.Padding = Padding.Empty; b.Margin = Padding.Empty;
            b.UseCompatibleTextRendering = false;
        }
        Button MakeButton(string text, int x, int y, int w, int h, Color fill, Font f, Control parent)
        {
            Button b = new Button();
            b.Text = text; b.Location = new Point(x, y); b.Size = new Size(w, h);
            StyleButton(b, fill); if (f != null) b.Font = f;
            (parent ?? (Control)this).Controls.Add(b); return b;
        }
        TextBox MakeTextBox(string val, int x, int y, int w)
        {
            TextBox t = new TextBox();
            t.AutoSize = false; t.Text = val; t.Location = new Point(x, y); t.Size = new Size(w, 24);
            t.BackColor = cPanel; t.ForeColor = cText; t.BorderStyle = BorderStyle.FixedSingle;
            Controls.Add(t); return t;
        }
        void DigitsOnly(TextBox t, bool allowDot)
        {
            t.KeyPress += delegate (object s, KeyPressEventArgs e)
            {
                if (char.IsControl(e.KeyChar)) return;
                if (char.IsDigit(e.KeyChar)) return;
                if (allowDot && e.KeyChar == '.') return;
                e.Handled = true;   // block anything else (letters, symbols, space)
            };
            t.TextChanged += delegate   // also sanitize pasted / programmatic text
            {
                string orig = t.Text;
                StringBuilder sb = new StringBuilder();
                foreach (char c in orig) { if (char.IsDigit(c) || (allowDot && c == '.')) sb.Append(c); }
                string cleaned = sb.ToString();
                if (cleaned != orig)
                {
                    int sel = t.SelectionStart - (orig.Length - cleaned.Length);
                    if (sel < 0) sel = 0;
                    t.Text = cleaned;
                    t.SelectionStart = Math.Min(sel, cleaned.Length);
                }
            };
        }
        Button MakeToggle(string txt, int x, int y, int w)
        {
            Button b = new Button();
            b.Text = txt; b.Location = new Point(x, y); b.Size = new Size(w, 26);
            StyleButton(b, cPanel); b.Font = fSmall; b.Tag = false;
            b.Click += delegate { bool v = !(bool)b.Tag; b.Tag = v; b.BackColor = v ? cAccent : cPanel; };
            Controls.Add(b); return b;
        }

        void BuildUi()
        {
            MakeLabel("  Phone Connect", 0, 12, 180, 28, fBig, cAccent, null);
            MakeLabel("Connect by", 14, 44, 68, 18, fSmall, cMuted, null);
            btnModeUsb = MakeButton("USB", 84, 40, 70, 24, cPanel, fSmall, null);
            btnModeCode = MakeButton("Wi-Fi code", 156, 40, 96, 24, cAccent, fSmall, null);
            btnModeQr = MakeButton("QR code", 254, 40, 84, 24, cPanel, fSmall, null);

            btnCheckUpd = MakeButton("Check update", 232, 12, 92, 26, cPanel, fSmall, null);
            btnHelp = MakeButton("How to use", 330, 12, 88, 26, cAccent, fSmall, null);
            btnShortcut = MakeButton("Add shortcut", 424, 12, 96, 26, cPanel, fSmall, null);
            btnCheckUpd.BringToFront(); btnHelp.BringToFront(); btnShortcut.BringToFront();
            btnUpdate = MakeButton("Update scrcpy", 270, 148, 122, 28, cGreen, fSmall, null);
            btnUpdate.Visible = false;

            // connect section
            lblIp = MakeLabel("IP address", 14, 70, 118, 18, fSmall, cMuted, null);
            lblPort = MakeLabel("Port", 138, 70, 58, 18, fSmall, cMuted, null);
            lblPcode = MakeLabel("Pairing code", 202, 70, 140, 18, fSmall, cMuted, null);
            txtIp = MakeTextBox(cfgIp, 14, 89, 118);
            txtPort = MakeTextBox("", 138, 89, 58);
            txtCode = MakeTextBox("", 202, 89, 94);
            btnConnect = MakeButton("Connect", 302, 89, 102, 24, cAccent, fSmall, null);
            btnDisconnect = MakeButton("Disconnect", 410, 89, 110, 24, cPanel, fSmall, null);
            lblCodeHelp = MakeLabel("Enter IP, Port & 6-digit code from 'Pair device with pairing code'.", 14, 116, 506, 18, fSmall, cMuted, null);

            // utility
            btnDevices = MakeButton("Check devices", 14, 148, 120, 28, cPanel, null, null);
            btnRestart = MakeButton("Restart ADB", 142, 148, 120, 28, cPanel, null, null);

            // usb mode
            lblUsbHelp = MakeLabel("Enable USB debugging, plug in, tap Allow on the phone, then Detect. See How to use for details.", 14, 70, 506, 36, fSmall, cMuted, null);
            btnUsb = MakeButton("Detect USB device", 14, 108, 506, 32, cAccent, null, null);

            // qr overlay
            qrPanel = new Panel();
            qrPanel.Location = new Point(8, 64); qrPanel.Size = new Size(524, 278); qrPanel.BackColor = cBg;
            Controls.Add(qrPanel);
            lblQrHelp = MakeLabel("Phone: Wireless debugging > Pair device with QR code, then scan the code below.", 6, 2, 512, 32, fSmall, cMuted, qrPanel);
            qrWeb = new WebBrowser();
            qrWeb.Location = new Point(162, 36); qrWeb.Size = new Size(200, 200); qrWeb.ScrollBarsEnabled = false;
            qrWeb.IsWebBrowserContextMenuEnabled = false; qrWeb.WebBrowserShortcutsEnabled = false; qrWeb.AllowWebBrowserDrop = false;
            qrPanel.Controls.Add(qrWeb);
            btnQrStart = MakeButton("Show QR code", 96, 242, 160, 30, cAccent, null, qrPanel);
            btnQrStop = MakeButton("Stop", 268, 242, 160, 30, cPanel, null, qrPanel);

            // mirroring options
            MakeLabel("Mirroring options", 14, 188, 160, 18, null, cAccent, null);
            btnOnTop = MakeToggle("Always on top", 14, 212, 110);
            btnHiRes = MakeToggle("High resolution", 130, 212, 116);
            btnNoAudio = MakeToggle("No audio", 252, 212, 72);
            btnMaxFps = MakeToggle("Limit FPS", 330, 212, 74);
            txtMaxFps = MakeTextBox("30", 410, 213, 40);
            txtMaxFps.TextAlign = HorizontalAlignment.Center;   // center the FPS number
            btnHiRes.Tag = true; btnHiRes.BackColor = cAccent;

            // restrict input: IP allows digits + dots; Port / Pairing code / FPS are digits only
            DigitsOnly(txtIp, true);
            DigitsOnly(txtPort, false);
            DigitsOnly(txtCode, false);
            DigitsOnly(txtMaxFps, false);

            // recording row
            btnRecord = MakeButton("Record", 14, 240, 160, 24, cPanel, null, null);
            btnShot = MakeButton("Screenshot", 184, 240, 160, 24, cPanel, null, null);
            btnOpenRec = MakeButton("Open folder", 14, 266, 160, 24, cPanel, fSmall, null);
            btnOpenShot = MakeButton("Open folder", 184, 266, 160, 24, cPanel, fSmall, null);

            // start
            btnStart = MakeButton("Start Mirroring", 14, 294, 506, 44, cGreen, fBig, null);
            lblNoDevice = MakeLabel("No device detected - connect your phone first (USB / Wi-Fi code / QR code).", 14, 340, 506, 18, fSmall, cRed, null);
            lblNoDevice.TextAlign = ContentAlignment.MiddleCenter; lblNoDevice.Visible = false;

            // logs
            MakeLabel("Activity", 14, 360, 240, 18, fSmall, cMuted, null);
            MakeLabel("Live output", 264, 360, 130, 18, fSmall, cMuted, null);
            lblFps = MakeLabel("FPS: --", 398, 360, 122, 18, fSmall, Color.FromArgb(130, 200, 235), null);
            lblFps.TextAlign = ContentAlignment.MiddleRight;
            log = new RichTextBox();
            log.Location = new Point(14, 380); log.Size = new Size(242, 150);
            log.ScrollBars = RichTextBoxScrollBars.Vertical; log.ReadOnly = true; log.WordWrap = true; log.DetectUrls = false;
            log.BorderStyle = BorderStyle.FixedSingle; log.BackColor = Color.FromArgb(20, 20, 26); log.ForeColor = cGreen; log.Font = fMono;
            Controls.Add(log);
            scrcpyLog = new TextBox();
            scrcpyLog.Location = new Point(264, 380); scrcpyLog.Size = new Size(256, 150);
            scrcpyLog.Multiline = true; scrcpyLog.ScrollBars = ScrollBars.Vertical; scrcpyLog.ReadOnly = true; scrcpyLog.WordWrap = true;
            scrcpyLog.BackColor = Color.FromArgb(20, 20, 26); scrcpyLog.ForeColor = Color.FromArgb(130, 200, 235); scrcpyLog.Font = fMono;
            Controls.Add(scrcpyLog);

            statusBar = MakeLabel("Ready.", 14, 536, 380, 20, fSmall, cMuted, null);
            lblVer = MakeLabel("", 400, 536, 120, 20, fSmall, cMuted, null);
            lblVer.TextAlign = ContentAlignment.MiddleRight;

            devTimer = new System.Windows.Forms.Timer(); devTimer.Interval = 1500;
            devTimer.Tick += delegate {
                if (lblNoDevice.Visible)
                    Task.Run((Action)delegate {
                        if (IsDeviceConnected())
                            UI(delegate { if (lblNoDevice.Visible) { lblNoDevice.Visible = false; statusBar.Text = "Device detected."; } });
                    });
            };

            WireEvents();
        }

        void WireEvents()
        {
            btnModeUsb.Click += delegate { SetMode("usb"); };
            btnModeCode.Click += delegate { SetMode("code"); };
            btnModeQr.Click += delegate { SetMode("qr"); };

            btnConnect.Click += delegate { OnConnect(); };
            btnDisconnect.Click += delegate { OnDisconnect(); };
            btnUsb.Click += delegate { OnDetectUsb(); };
            btnDevices.Click += delegate { SetStatus("Listing devices ..."); Task.Run((Action)delegate { AdbLogged(new string[] { "devices", "-l" }); SetStatus("Ready."); }); };
            btnRestart.Click += delegate { Task.Run((Action)delegate { SetStatus("Stopping ADB ..."); AdbLogged(new string[] { "kill-server" }); SetStatus("Starting ADB ..."); AdbLogged(new string[] { "start-server" }); Log("ADB restarted."); SetStatus("Ready."); }); };

            btnQrStart.Click += delegate { OnQrStart(); };
            btnQrStop.Click += delegate { StopQrPolling(); ClearQrImage(); Log("QR pairing stopped."); SetStatus("Ready."); };

            btnHelp.Click += delegate { ShowGuide(); };
            btnShortcut.Click += delegate { OnAddShortcut(); };
            btnCheckUpd.Click += delegate { OnCheckUpdate(); };
            btnUpdate.Click += delegate { OnUpdate(); };

            btnStart.Click += delegate { OnStartStop(); };
            btnRecord.Click += delegate { OnRecord(); };
            btnShot.Click += delegate { TakeScreenshot(); };
            btnOpenRec.Click += delegate { OpenFolder(RecordDir); };
            btnOpenShot.Click += delegate { OpenFolder(ShotDir); };
        }

        // ---------- logging ----------
        void Log(string msg) { Log(msg, null); }
        void Log(string msg, string level) { string m = msg; string lv = level; UI(delegate { AppendLog(m, lv); }); }
        void SetStatus(string s) { UI(delegate { statusBar.Text = s; }); }
        void AppendLog(string msg, string level)
        {
            string ts = DateTime.Now.ToString("HH:mm:ss");
            if (level == null)
            {
                if (Regex.IsMatch(msg, @"\b(error|fail|failed|cannot|not found|missing|no device|offline|unauthorized|denied|timed out|interrupted)\b", RegexOptions.IgnoreCase)) level = "err";
                else if (Regex.IsMatch(msg, @"\b(warning|not saved|could not|retry|stopped)\b", RegexOptions.IgnoreCase)) level = "warn";
                else if (Regex.IsMatch(msg, @"\b(success|saved|connected|reconnected|paired|detected|ready|done|started|mirroring|recording to)\b", RegexOptions.IgnoreCase)) level = "ok";
                else level = "info";
            }
            Color col = level == "err" ? cErr : level == "warn" ? cWarn : level == "ok" ? cOk : cInfo;
            log.SelectionStart = log.TextLength; log.SelectionLength = 0; log.SelectionColor = cMuted; log.SelectionFont = log.Font;
            log.AppendText("[" + ts + "] ");
            log.SelectionStart = log.TextLength; log.SelectionLength = 0; log.SelectionColor = col;
            log.SelectionFont = (level == "err" || level == "ok") ? new Font(log.Font, FontStyle.Bold) : log.Font;
            log.AppendText(msg + "\r\n");
            log.SelectionStart = log.TextLength; log.SelectionLength = 0; log.SelectionColor = log.ForeColor; log.SelectionFont = log.Font;
            log.ScrollToCaret();
        }

        // ---------- process helpers ----------
        string QuoteArgs(IEnumerable<string> a)
        {
            List<string> parts = new List<string>();
            foreach (string s in a)
            {
                if (s.IndexOfAny(new char[] { ' ', '\t', '"' }) >= 0) parts.Add("\"" + s.Replace("\"", "\\\"") + "\"");
                else parts.Add(s);
            }
            return string.Join(" ", parts.ToArray());
        }
        string RunCapture(string exe, string args) { return RunCapture(exe, args, 15000); }
        string RunCapture(string exe, string args, int timeoutMs)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe, args);
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.WorkingDirectory = ScriptDir;
                StringBuilder sb = new StringBuilder();
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.OutputDataReceived += delegate (object s, DataReceivedEventArgs e) { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
                    p.ErrorDataReceived += delegate (object s, DataReceivedEventArgs e) { if (e.Data != null) lock (sb) sb.AppendLine(e.Data); };
                    p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
                    if (!p.WaitForExit(timeoutMs)) { try { p.Kill(); } catch { } }
                    else { p.WaitForExit(800); }
                    return sb.ToString().Trim();
                }
            }
            catch (Exception ex) { return "ERROR: " + ex.Message; }
        }
        void AdbLogged(string[] args)
        {
            if (!File.Exists(Adb)) { Log("ERROR: adb.exe not found next to this tool."); return; }
            Log(">> adb " + string.Join(" ", args));
            string outp = RunCapture(Adb, QuoteArgs(args));
            if (outp.Length > 0) Log(outp);
        }
        bool IsDeviceConnected()
        {
            if (!File.Exists(Adb)) return false;
            string outp = RunCapture(Adb, "devices");
            foreach (string raw in outp.Split('\n'))
            {
                string ln = raw.Trim();
                if (ln.StartsWith("List")) continue;
                if (Regex.IsMatch(ln, @"\sdevice$")) return true;
            }
            return false;
        }
        string GetLocalScrcpyVersion()
        {
            if (!File.Exists(Scrcpy)) return null;
            string v = RunCapture(Scrcpy, "--version", 8000);
            Match m = Regex.Match(v, @"scrcpy\s+v?([0-9]+(?:\.[0-9]+)+)");
            return m.Success ? m.Groups[1].Value : null;
        }
        string GetLatestReleaseJson()
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create("https://api.github.com/repos/Genymobile/scrcpy/releases/latest");
            req.UserAgent = "PhoneConnect"; req.Accept = "application/vnd.github+json"; req.Timeout = 20000;
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (StreamReader sr = new StreamReader(resp.GetResponseStream()))
                return sr.ReadToEnd();
        }

        // ---------- config ----------
        void LoadConfig()
        {
            cfgIp = "192.168.18.2";
            try
            {
                if (File.Exists(ConfigPath))
                {
                    string s = File.ReadAllText(ConfigPath);
                    Match m = Regex.Match(s, "\"connectIp\"\\s*:\\s*\"([^\"]*)\"");
                    if (m.Success && m.Groups[1].Value.Length > 0) cfgIp = m.Groups[1].Value;
                }
            }
            catch { }
        }
        void SaveConfig(string ip, string port)
        {
            try { File.WriteAllText(ConfigPath, "{\"connectIp\":\"" + JsonEsc(ip) + "\",\"connectPort\":\"" + JsonEsc(port) + "\"}"); } catch { }
        }
        string JsonEsc(string s) { if (s == null) return ""; return s.Replace("\\", "\\\\").Replace("\"", "\\\""); }

        // ---------- modes ----------
        void SetMode(string m)
        {
            mode = m; bool isCode = m == "code", isUsb = m == "usb", isQr = m == "qr";
            Control[] codeCtl = new Control[] { lblIp, lblPort, lblPcode, txtIp, txtPort, txtCode, btnConnect, btnDisconnect, lblCodeHelp };
            foreach (Control c in codeCtl) c.Visible = isCode;
            lblUsbHelp.Visible = isUsb; btnUsb.Visible = isUsb;
            qrPanel.Visible = isQr;
            if (isQr) qrPanel.BringToFront(); else ClearQrImage();
            Color on = Color.White;
            btnModeUsb.BackColor = isUsb ? cAccent : cPanel; btnModeUsb.ForeColor = isUsb ? on : cMuted;
            btnModeCode.BackColor = isCode ? cAccent : cPanel; btnModeCode.ForeColor = isCode ? on : cMuted;
            btnModeQr.BackColor = isQr ? cAccent : cPanel; btnModeQr.ForeColor = isQr ? on : cMuted;
            if (!isUsb) usbSerial = null;
            if (!isQr) StopQrPolling();
            statusBar.Text = isUsb ? "USB mode." : isQr ? "QR-code mode." : "Wi-Fi (code) mode.";
        }

        // ---------- connect / usb ----------
        void OnConnect()
        {
            string ip = txtIp.Text.Trim(), port = txtPort.Text.Trim(), code = txtCode.Text.Trim();
            if (ip.Length == 0) { Log("Enter the IP address, e.g. 192.168.18.2"); return; }
            if (!Regex.IsMatch(port, @"^\d+$")) { Log("Enter the numeric Port, e.g. 37123"); return; }
            usbSerial = null; SaveConfig(ip, port);
            string addr = ip + ":" + port;
            SetStatus(code.Length > 0 ? "Pairing with " + addr + " ..." : "Connecting to " + addr + " ...");
            Task.Run((Action)delegate {
                if (code.Length > 0)
                {
                    AdbLogged(new string[] { "pair", addr, code });
                    Sleep(1800);
                    Log("Checking whether the phone connected ...");
                    AdbLogged(new string[] { "devices", "-l" });
                    Log("If a device is listed above you are ready - just Start Mirroring.");
                }
                else AdbLogged(new string[] { "connect", addr });
                Sleep(400);
                if (IsDeviceConnected()) UI(delegate { lblNoDevice.Visible = false; });
                SetStatus("Ready.");
            });
        }
        void OnDisconnect()
        {
            string ip = txtIp.Text.Trim(), port = txtPort.Text.Trim();
            usbSerial = null; SetStatus("Disconnecting ...");
            Task.Run((Action)delegate {
                if (ip.Length > 0 && Regex.IsMatch(port, @"^\d+$")) AdbLogged(new string[] { "disconnect", ip + ":" + port });
                else AdbLogged(new string[] { "disconnect" });
                Sleep(400);
                if (!IsDeviceConnected()) { UI(delegate { lblNoDevice.Visible = true; }); SetStatus("Disconnected - no device."); }
                else { UI(delegate { lblNoDevice.Visible = false; }); SetStatus("A device is still connected."); }
            });
        }
        void OnDetectUsb()
        {
            if (!File.Exists(Adb)) { Log("ERROR: adb.exe not found next to this tool."); return; }
            SetStatus("Checking USB ..."); Log(">> adb devices -l");
            Task.Run((Action)delegate {
                try
                {
                    string outp = RunCapture(Adb, "devices -l"); if (outp.Length > 0) Log(outp);
                    string found = null;
                    foreach (string raw in outp.Split('\n'))
                    {
                        string ln = raw.Trim();
                        if (ln.StartsWith("List")) continue;
                        Match m = Regex.Match(ln, @"^(\S+)\s+device\b");
                        if (m.Success) { string serial = m.Groups[1].Value; if (!Regex.IsMatch(serial, @":\d+$")) { found = serial; break; } }
                    }
                    if (found != null) { usbSerial = found; Log("USB device ready: " + found + ".  Click Start Mirroring."); SetStatus("USB device: " + found); }
                    else { usbSerial = null; Log("No USB device found. Plug in the phone, enable USB debugging, and tap \"Allow\" on the phone."); SetStatus("No USB device."); }
                }
                catch (Exception ex) { Log("ERROR: " + ex.Message); SetStatus("Error - see output."); }
            });
        }

        // ---------- QR ----------
        void ClearQrImage() { try { qrWeb.DocumentText = "<html><body style='background:#1e1e26;margin:0'></body></html>"; } catch { } }
        void StopQrPolling() { if (qrTimer != null) { qrTimer.Stop(); qrTimer.Dispose(); qrTimer = null; } qrBusy = false; }
        string QrHtml(string content, string lib)
        {
            return "<!-- saved from url=(0014)about:internet -->\r\n" +
                "<!doctype html><html><head><meta charset='utf-8'>\r\n" +
                "<style>html,body{margin:0;background:#fff;overflow:hidden}\r\n" +
                "#qr{position:absolute;top:0px;left:0px;width:200px;height:200px}\r\n" +
                "#qr table{margin:0 auto;border-collapse:collapse}#qr img{display:block;margin:0 auto}</style></head>\r\n" +
                "<body><div id='qr'></div>\r\n" +
                "<script>" + lib + "</script>\r\n" +
                "<script>new QRCode(document.getElementById('qr'),{text:'" + content + "',width:200,height:200,correctLevel:QRCode.CorrectLevel.L});</script>\r\n" +
                "</body></html>";
        }
        void OnQrStart()
        {
            if (!File.Exists(Adb)) { Log("ERROR: adb.exe not found next to this tool."); return; }
            if (!File.Exists(QrLib)) { Log("ERROR: qrcode.min.js is missing, cannot draw the QR."); return; }
            string rng = Guid.NewGuid().ToString("N");
            qrService = "ADB_WIFI_" + rng.Substring(0, 8); qrPassword = rng.Substring(8, 12);
            string content = "WIFI:T:ADB;S:" + qrService + ";P:" + qrPassword + ";;";
            string lib = File.ReadAllText(QrLib);
            StopQrPolling(); qrTries = 0;
            try { qrWeb.DocumentText = QrHtml(content, lib); } catch (Exception ex) { Log("ERROR drawing QR: " + ex.Message); return; }
            Log("QR shown in the app window. On the phone: Wireless debugging > Pair device with QR code, then scan it.");
            SetStatus("Waiting for the phone to scan ...");
            qrTimer = new System.Windows.Forms.Timer(); qrTimer.Interval = 1500;
            qrTimer.Tick += QrTick; qrTimer.Start();
        }
        void QrTick(object s, EventArgs e)
        {
            qrTries++;
            if (qrTries > 60) { StopQrPolling(); Log("QR pairing timed out (90s). Click \"Show QR code\" to try again."); SetStatus("QR timed out."); return; }
            if (qrBusy) return; qrBusy = true;
            Task.Run((Action)delegate {
                try
                {
                    string svc = RunCapture(Adb, "mdns services");
                    string ipport = null;
                    foreach (string raw in svc.Split('\n'))
                    {
                        string ln = raw.Trim();
                        if (ln.IndexOf("adb-tls-pairing", StringComparison.OrdinalIgnoreCase) >= 0)
                        {
                            string[] rawParts = Regex.Split(ln, @"\s+");
                            List<string> parts = new List<string>();
                            foreach (string pp in rawParts) if (pp.Length > 0) parts.Add(pp);
                            if (parts.Count >= 3)
                            {
                                string name = parts[0]; string addr = parts[parts.Count - 1];
                                if (name == qrService) { ipport = addr; break; }
                                else if (ipport == null) ipport = addr;
                            }
                        }
                    }
                    if (ipport != null)
                    {
                        UI(delegate { StopQrPolling(); });
                        Log("Phone detected at " + ipport + " - pairing ..."); SetStatus("Pairing ...");
                        string outp = RunCapture(Adb, "pair " + ipport + " " + qrPassword); if (outp.Length > 0) Log(outp);
                        Sleep(1200);
                        string dev = RunCapture(Adb, "devices -l"); if (dev.Length > 0) Log(dev);
                        if (outp.IndexOf("Successfully paired", StringComparison.OrdinalIgnoreCase) >= 0)
                        { Log("Paired via QR. The phone auto-connects shortly - then click Start Mirroring."); SetStatus("QR paired."); UI(delegate { SetMode("code"); }); }
                        else SetStatus("QR pairing finished - see output.");
                    }
                }
                catch (Exception ex) { UI(delegate { StopQrPolling(); }); Log("ERROR during QR pairing: " + ex.Message); SetStatus("Error - see output."); }
                finally { qrBusy = false; }
            });
        }

        // ---------- mirroring / recording ----------
        bool IsMirroring() { return scrcpyProc != null && !scrcpyProc.HasExited; }
        void SetMirrorButton(bool running)
        {
            if (running) { btnStart.Text = "Stop Mirroring"; btnStart.BackColor = cRed; }
            else { btnStart.Text = "Start Mirroring"; btnStart.BackColor = cGreen; }
        }
        void SetRecIndicator()
        {
            if (recording) { btnRecord.Text = "Stop rec"; btnRecord.BackColor = cRed; }
            else { btnRecord.Text = "Record"; btnRecord.BackColor = cPanel; }
        }
        void ReportRecording(string f)
        {
            if (f != null && File.Exists(f))
            { double mb = Math.Round(new FileInfo(f).Length / 1048576.0, 1); Log("Recording saved: " + f + "  (" + mb + " MB)"); SetStatus("Recording saved."); }
            else { Log("WARNING: no recording file was created - see the scrcpy> lines above for the reason: " + f); SetStatus("Recording not saved."); }
        }
        List<string> BuildArgs(bool onTop, bool hiRes, bool noAudio, bool limitFps, string fpsText, string serial, string recordPath)
        {
            List<string> o = new List<string>();
            if (!string.IsNullOrEmpty(serial)) { o.Add("-s"); o.Add(serial); }
            if (onTop) o.Add("--always-on-top");
            if (!hiRes) { o.Add("--max-size"); o.Add("1280"); o.Add("--video-bit-rate"); o.Add("4M"); o.Add("--video-codec"); o.Add("h264"); }
            if (noAudio) o.Add("--no-audio");
            o.Add("--print-fps");
            if (limitFps) { string f = fpsText.Trim(); if (Regex.IsMatch(f, @"^\d+$")) o.Add("--max-fps=" + f); }
            if (!string.IsNullOrEmpty(recordPath)) { o.Add("--record"); o.Add(recordPath); }
            return o;
        }
        void StartMirror(string recordPath)
        {
            if (!File.Exists(Scrcpy)) { Log("ERROR: scrcpy.exe not found next to this tool."); return; }
            bool onTop = (bool)btnOnTop.Tag, hiRes = (bool)btnHiRes.Tag, noAudio = (bool)btnNoAudio.Tag, limitFps = (bool)btnMaxFps.Tag;
            string fpsText = txtMaxFps.Text, serial = usbSerial, ip = txtIp.Text.Trim(), port = txtPort.Text.Trim();
            btnStart.Enabled = false; btnRecord.Enabled = false;
            Task.Run((Action)delegate {
                try
                {
                    if (!IsDeviceConnected())
                    {
                        if (ip.Length > 0 && Regex.IsMatch(port, @"^\d+$"))
                        {
                            Log("No device - trying to reconnect to " + ip + ":" + port + " ..."); SetStatus("Reconnecting ...");
                            string r = RunCapture(Adb, "connect " + ip + ":" + port); if (r.Length > 0) Log(r); Sleep(1300);
                        }
                        if (!IsDeviceConnected())
                        {
                            UI(delegate { lblNoDevice.Visible = true; });
                            Log("No device detected. Connect your phone first (USB / Wi-Fi code / QR code).");
                            SetStatus("No device detected.");
                            UI(delegate { btnStart.Enabled = true; btnRecord.Enabled = true; });
                            return;
                        }
                        Log("Reconnected.");
                    }
                    List<string> args = BuildArgs(onTop, hiRes, noAudio, limitFps, fpsText, serial, recordPath);
                    Log(">> scrcpy " + string.Join(" ", args.ToArray()));
                    string rp = recordPath;
                    UI(delegate {
                        lblNoDevice.Visible = false;
                        StartScrcpyProcess(args, rp);
                        btnStart.Enabled = true; btnRecord.Enabled = true;
                    });
                }
                catch (Exception ex) { Log("ERROR: " + ex.Message); UI(delegate { btnStart.Enabled = true; btnRecord.Enabled = true; }); }
            });
        }
        void StartScrcpyProcess(List<string> args, string recordPath)
        {
            try
            {
                scrcpyLog.Clear(); lblFps.Text = "FPS: --";
                ProcessStartInfo psi = new ProcessStartInfo(Scrcpy, QuoteArgs(args));
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.WorkingDirectory = ScriptDir;
                Process p = new Process(); p.StartInfo = psi;
                p.OutputDataReceived += OnScrcpyData; p.ErrorDataReceived += OnScrcpyData;
                p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
                scrcpyProc = p; recording = !string.IsNullOrEmpty(recordPath); recordFile = recordPath;
                SetMirrorButton(true); SetRecIndicator(); StartWatch();
                if (recording) { Log("Recording to " + recordPath); Log("Click Stop rec (or close the mirror window) to save it."); SetStatus("Recording ..."); }
                else { Log("scrcpy launched. Click Stop Mirroring (or close the mirror window) to stop."); SetStatus("Mirroring."); }
            }
            catch (Exception ex) { Log("ERROR: " + ex.Message); SetMirrorButton(false); recording = false; SetRecIndicator(); }
        }
        void OnScrcpyData(object s, DataReceivedEventArgs e)
        {
            if (e.Data == null) return; string line = e.Data; UI(delegate { HandleScrcpyLine(line); });
        }
        void HandleScrcpyLine(string line)
        {
            if (line.Length == 0) return;
            Match m = Regex.Match(line, @"(\d+)\s+fps");
            if (m.Success) lblFps.Text = "FPS: " + m.Groups[1].Value;
            else if (line.IndexOf("FPS counter started", StringComparison.OrdinalIgnoreCase) >= 0) lblFps.Text = "FPS: 0";
            else scrcpyLog.AppendText(line + "\r\n");
        }
        void StartWatch()
        {
            StopWatch();
            mirrorTimer = new System.Windows.Forms.Timer(); mirrorTimer.Interval = 1000;
            mirrorTimer.Tick += delegate { if (scrcpyProc != null && !stopping && scrcpyProc.HasExited) MirrorEndedExternal(); };
            mirrorTimer.Start();
        }
        void StopWatch() { if (mirrorTimer != null) { mirrorTimer.Stop(); mirrorTimer.Dispose(); mirrorTimer = null; } }
        void MirrorEndedExternal()
        {
            StopWatch();
            bool wasRec = recording; string f = recordFile;
            try { if (scrcpyProc != null) scrcpyProc.Dispose(); } catch { }
            scrcpyProc = null; recording = false;
            SetMirrorButton(false); SetRecIndicator();
            if (wasRec) ReportRecording(f); else { Log("Mirror window closed."); SetStatus("Ready."); }
        }
        void StopMirror(Action<bool, string> onDone)
        {
            Process proc = scrcpyProc; bool wasRec = recording; string f = recordFile;
            if (proc == null) { onDone(wasRec, f); return; }
            stopping = true; StopWatch();
            btnStart.Enabled = false; btnRecord.Enabled = false;
            if (wasRec) { Log("Finalizing recording ..."); SetStatus("Finalizing recording ..."); }
            Task.Run((Action)delegate {
                try
                {
                    if (!proc.HasExited)
                    {
                        int w = 0;
                        while (w < 40 && !proc.HasExited) { try { proc.Refresh(); } catch { } if (proc.MainWindowHandle != IntPtr.Zero) break; Sleep(100); w++; }
                        try { proc.CloseMainWindow(); } catch { }
                        int n = 0;
                        while (!proc.HasExited && n < 120) { Sleep(100); n++; }
                        if (!proc.HasExited) { try { proc.Kill(); } catch { } if (wasRec) Log("scrcpy did not close gracefully - recording may be incomplete."); }
                    }
                }
                catch { }
                Sleep(200);
                UI(delegate {
                    try { proc.Dispose(); } catch { }
                    scrcpyProc = null; recording = false; stopping = false;
                    SetMirrorButton(false); SetRecIndicator();
                    btnStart.Enabled = true; btnRecord.Enabled = true;
                    onDone(wasRec, f);
                });
            });
        }
        void OnStartStop()
        {
            if (!File.Exists(Scrcpy)) { Log("ERROR: scrcpy.exe not found next to this tool."); return; }
            if (IsMirroring())
                StopMirror(delegate (bool wasRec, string f) { if (wasRec) ReportRecording(f); else { Log("Mirror stopped."); SetStatus("Mirror stopped."); } });
            else StartMirror(null);
        }
        void OnRecord()
        {
            if (!File.Exists(Scrcpy)) { Log("ERROR: scrcpy.exe not found next to this tool."); return; }
            if (IsMirroring() && recording) { StopMirror(delegate (bool wasRec, string f) { ReportRecording(f); }); return; }
            if (IsMirroring()) { Log("Stopping the plain mirror to start a recording ..."); StopMirror(delegate (bool wasRec, string f) { StartRecordingNow(); }); return; }
            StartRecordingNow();
        }
        void StartRecordingNow()
        {
            try { if (!Directory.Exists(RecordDir)) Directory.CreateDirectory(RecordDir); } catch { }
            string file = Path.Combine(RecordDir, "scrcpy_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss") + ".mkv");
            StartMirror(file);
        }

        // ---------- screenshot / folders ----------
        void TakeScreenshot()
        {
            if (!File.Exists(Adb)) { Log("ERROR: adb.exe not found next to this tool."); return; }
            string serial = usbSerial;
            SetStatus("Taking screenshot ..."); Log(">> adb screencap");
            Task.Run((Action)delegate {
                try
                {
                    if (!Directory.Exists(ShotDir)) Directory.CreateDirectory(ShotDir);
                    string local = Path.Combine(ShotDir, "shot_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss") + ".png");
                    string remote = "/sdcard/__pc_shot.png";
                    List<string> sel = new List<string>();
                    if (!string.IsNullOrEmpty(serial)) { sel.Add("-s"); sel.Add(serial); }
                    string e1 = RunCapture(Adb, QuoteArgs(Merge(sel, new string[] { "shell", "screencap", "-p", remote }))); if (e1.Length > 0) Log(e1);
                    string e2 = RunCapture(Adb, QuoteArgs(Merge(sel, new string[] { "pull", remote, local }))); if (e2.Length > 0) Log(e2);
                    RunCapture(Adb, QuoteArgs(Merge(sel, new string[] { "shell", "rm", remote })));
                    if (File.Exists(local)) { Log("Screenshot saved: " + local); SetStatus("Screenshot saved."); }
                    else { Log("Screenshot failed - is a device connected?"); SetStatus("Screenshot failed."); }
                }
                catch (Exception ex) { Log("ERROR: " + ex.Message); SetStatus("Error - see output."); }
            });
        }
        string[] Merge(List<string> a, string[] b) { List<string> l = new List<string>(a); l.AddRange(b); return l.ToArray(); }
        void OpenFolder(string dir)
        {
            try { if (!Directory.Exists(dir)) Directory.CreateDirectory(dir); Process.Start("explorer.exe", dir); }
            catch (Exception ex) { Log("ERROR opening folder: " + ex.Message); }
        }

        // ---------- shortcut ----------
        void OnAddShortcut()
        {
            try
            {
                string[][] targets = new string[][] {
                    new string[] { "Desktop",    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop),  "Phone Connect.lnk") },
                    new string[] { "Start menu", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Phone Connect.lnk") }
                };
                Type t = Type.GetTypeFromProgID("WScript.Shell");
                object shell = Activator.CreateInstance(t);
                foreach (string[] tg in targets)
                {
                    string where = tg[0], lnkPath = tg[1];
                    try { string d = Path.GetDirectoryName(lnkPath); if (!Directory.Exists(d)) Directory.CreateDirectory(d); } catch { }
                    object lnk = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
                    Type lt = lnk.GetType();
                    lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { ExePath });
                    lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { ScriptDir });
                    lt.InvokeMember("WindowStyle", BindingFlags.SetProperty, null, lnk, new object[] { 1 });
                    lt.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { "Phone Connect - scrcpy + adb" });
                    if (File.Exists(IconPath)) lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { IconPath + ",0" });
                    else if (File.Exists(Scrcpy)) lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { Scrcpy + ",0" });
                    lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
                    Log(where + " shortcut created: " + lnkPath, "ok");
                }
                SetStatus("Shortcuts added (Desktop + Start menu).");
            }
            catch (Exception ex) { Log("ERROR creating shortcut: " + ex.Message); SetStatus("Error - see output."); }
        }

        // ---------- updates ----------
        void OnCheckUpdate()
        {
            SetStatus("Checking for updates ..."); btnUpdate.Visible = false;
            Task.Run((Action)delegate {
                string local = GetLocalScrcpyVersion();
                if (local != null) Log("Installed scrcpy: " + local); else Log("Could not read the installed scrcpy version.");
                try
                {
                    string json = GetLatestReleaseJson();
                    Match mt = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
                    string tag = mt.Success ? mt.Groups[1].Value : "";
                    string latest = Regex.Replace(tag, "^v", "");
                    Log("Latest release: " + tag);
                    if (local != null)
                    {
                        Version vl, vL;
                        if (Version.TryParse(local, out vl) && Version.TryParse(latest, out vL))
                        {
                            if (vL > vl) { Log("Update available: " + local + " -> " + latest + ".  Click 'Update scrcpy'."); SetStatus("Update available: " + latest); UI(delegate { btnUpdate.Text = "Update to " + latest; btnUpdate.Visible = true; }); }
                            else if (vL == vl) { Log("You are on the latest version."); SetStatus("Up to date."); }
                            else { Log("Installed version is newer than the latest public release."); SetStatus("Up to date."); }
                        }
                        else { Log("Latest is " + latest + " (could not compare version numbers)."); SetStatus("Latest: " + latest); }
                    }
                    else SetStatus("Latest: " + latest);
                }
                catch (Exception ex) { Log("ERROR checking for updates: " + ex.Message); SetStatus("Error - see output."); }
            });
        }
        void OnUpdate()
        {
            Task.Run((Action)delegate {
                try
                {
                    SetStatus("Checking latest release ...");
                    string json = GetLatestReleaseJson();
                    Match mt = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"([^\"]+)\"");
                    string tag = mt.Success ? mt.Groups[1].Value : "";
                    Match ma = Regex.Match(json, "\"name\"\\s*:\\s*\"(scrcpy-win64-[^\"]*\\.zip)\"[\\s\\S]*?\"size\"\\s*:\\s*(\\d+)[\\s\\S]*?\"browser_download_url\"\\s*:\\s*\"([^\"]+)\"");
                    if (!ma.Success) { Log("No win64 .zip asset found in the latest release."); SetStatus("Ready."); return; }
                    string name = ma.Groups[1].Value; long size = long.Parse(ma.Groups[2].Value); string url = ma.Groups[3].Value;
                    double sizeMB = Math.Round(size / 1048576.0, 1);
                    string msg = "Download and install scrcpy " + tag + "?\r\n\r\nFile:   " + name + "\r\nSize:   " + sizeMB + " MB\r\nSource: github.com/Genymobile/scrcpy\r\n\r\nClose any open mirror window first.\r\nYour settings and notes are kept.";
                    DialogResult dr = DialogResult.Cancel;
                    Invoke((Action)delegate { dr = MessageBox.Show(this, msg, "Update scrcpy", MessageBoxButtons.OKCancel, MessageBoxIcon.Question); });
                    if (dr != DialogResult.OK) { Log("Update cancelled."); SetStatus("Ready."); return; }
                    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                    string tmp = Path.Combine(Path.GetTempPath(), "scrcpy_update_" + Guid.NewGuid().ToString("N"));
                    Directory.CreateDirectory(tmp);
                    string zip = Path.Combine(tmp, name);
                    Log("Downloading " + name + " (" + sizeMB + " MB) ..."); SetStatus("Downloading ...");
                    using (WebClient wc = new WebClient()) { wc.Headers.Add("User-Agent", "PhoneConnect"); wc.DownloadFile(url, zip); }
                    Log("Extracting ...");
                    string ex2 = Path.Combine(tmp, "extract"); ZipFile.ExtractToDirectory(zip, ex2);
                    string src = ex2; string[] dirs = Directory.GetDirectories(ex2); if (dirs.Length > 0) src = dirs[0];
                    try { RunCapture(Adb, "kill-server"); } catch { } Sleep(500);
                    Log("Installing new files ..."); SetStatus("Installing ...");
                    List<string> failed = new List<string>();
                    foreach (string file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
                    {
                        string rel = file.Substring(src.Length).TrimStart('\\', '/');
                        string dest = Path.Combine(ScriptDir, rel); string destDir = Path.GetDirectoryName(dest);
                        try { if (!Directory.Exists(destDir)) Directory.CreateDirectory(destDir); File.Copy(file, dest, true); } catch { failed.Add(rel); }
                    }
                    try { Directory.Delete(tmp, true); } catch { }
                    if (failed.Count > 0) { Log("Some files were in use and were NOT updated (close scrcpy, then retry): " + string.Join(", ", failed.ToArray())); SetStatus("Partial update - close scrcpy and retry."); }
                    else { string nv = GetLocalScrcpyVersion(); Log("Update complete. scrcpy is now: " + nv); SetStatus("Updated to " + nv); UI(delegate { btnUpdate.Visible = false; lblVer.Text = "scrcpy v" + nv; }); }
                }
                catch (Exception ex) { Log("ERROR updating: " + ex.Message); SetStatus("Error - see output."); }
            });
        }

        // ---------- guide ----------
        void ShowGuide()
        {
            Form gf = new Form();
            gf.Text = "Phone Connect - How to use"; gf.Size = new Size(620, 680);
            gf.StartPosition = FormStartPosition.CenterParent; gf.BackColor = Color.FromArgb(30, 30, 38);
            try { gf.Icon = this.Icon; } catch { }
            WebBrowser gw = new WebBrowser();
            gw.Dock = DockStyle.Fill; gw.IsWebBrowserContextMenuEnabled = false; gw.AllowWebBrowserDrop = false;
            gf.Controls.Add(gw); gw.DocumentText = GuideHtml();
            gf.Show(this);
        }
        string GuideHtml()
        {
            return @"<!-- saved from url=(0014)about:internet -->
<!doctype html><html><head><meta charset='utf-8'>
<style>
body{font-family:Segoe UI,Arial;background:#1e1e26;color:#e6e6eb;margin:0;padding:18px 22px;line-height:1.55}
h1{color:#58a6ff;font-size:20px;margin:0 0 4px}
h2{color:#58a6ff;font-size:15px;margin:18px 0 6px;border-bottom:1px solid #3a3a48;padding-bottom:3px}
p,li{font-size:13px;color:#d4d4dc} b{color:#fff}
ul{margin:4px 0 4px 0;padding-left:20px} li{margin:3px 0}
code{background:#2a2a36;color:#9fe1cb;padding:1px 5px;border-radius:4px;font-family:Consolas}
.muted{color:#9a9aa5;font-size:12px}
</style></head><body>
<h1>Phone Connect - How to use</h1>
<p class='muted'>Mirror and control your Android phone with scrcpy + adb. Pick a connection method, connect, then Start Mirroring.</p>

<h2>Connect by: USB</h2>
<ul>
<li>On the phone, enable <b>Developer options &gt; USB debugging</b>.</li>
<li>Plug the phone into the PC and tap <b>Allow</b> on the ""Allow USB debugging?"" prompt.</li>
<li>Click <b>Detect USB device</b>. When it is found, click <b>Start Mirroring</b>.</li>
<li>USB gives the lowest latency - use it if Wi-Fi feels laggy.</li>
</ul>

<h2>Connect by: Wi-Fi code</h2>
<ul>
<li>On the phone: <b>Developer options &gt; Wireless debugging</b> (turn it on).</li>
<li><b>First time (pairing):</b> open <b>Pair device with pairing code</b>. Enter that screen's IP in <b>IP address</b>, its Port in <b>Port</b>, and the 6-digit code in <b>Pairing code</b>, then <b>Connect</b>.</li>
<li><b>Reconnecting (already paired):</b> use the IP and Port shown on the <b>main</b> Wireless debugging screen, leave <b>Pairing code</b> blank, then <b>Connect</b>.</li>
<li>Note: the pairing Port and the connect Port are different numbers, and the Port changes each time Wireless debugging is toggled off/on.</li>
</ul>

<h2>Connect by: QR code</h2>
<ul>
<li>On the phone: <b>Wireless debugging &gt; Pair device with QR code</b>.</li>
<li>Click <b>Show QR code</b> and scan the code shown in the app. Pairing and connecting finish automatically.</li>
</ul>

<h2>Mirroring</h2>
<ul>
<li><b>Start Mirroring</b> opens the live screen; the button becomes <b>Stop Mirroring</b>. Closing the mirror window also stops it.</li>
<li>If no device is found it tries to reconnect to the last IP:Port; if that fails it shows ""No device detected"".</li>
<li><b>Always on top</b>: keep the mirror window above other windows.</li>
<li><b>High resolution</b> (on by default): full-resolution capture. Turn it off for a smaller, lower-latency stream (handy over Wi-Fi).</li>
<li><b>No audio</b>: turn on to drop audio for less overhead. <b>Limit FPS</b>: cap the frame rate to the number in the box.</li>
<li>These options apply to both mirroring and recording.</li>
</ul>

<h2>Recording &amp; screenshots</h2>
<ul>
<li><b>Record</b> starts a recording; the button turns red and reads <b>Stop rec</b>. Click it (or close the mirror window) to save.</li>
<li>Recordings save to <code>recordings\</code> as timestamped <code>.mkv</code> files. Use the <b>Open folder</b> button under <b>Record</b> to find them.</li>
<li><b>Screenshot</b> saves a PNG to <code>screenshots\</code>; its <b>Open folder</b> button opens that folder.</li>
</ul>

<h2>Output panels</h2>
<ul>
<li><b>Activity</b> (left): your clicks and plain-English results.</li>
<li><b>Live output</b> (right): scrcpy's live messages - useful if something fails.</li>
</ul>

<h2>Troubleshooting</h2>
<ul>
<li><b>No device detected:</b> reconnect (USB / Wi-Fi code / QR), then <b>Check devices</b>. If the phone's IP or Port changed, re-enter them.</li>
<li><b>Laggy / delayed:</b> turn off <b>High resolution</b> (and optionally on <b>No audio</b>), use 5 GHz Wi-Fi near the router, or connect by USB.</li>
<li><b>Connection stuck:</b> click <b>Restart ADB</b>, then connect again.</li>
<li><b>Recording didn't save:</b> use <b>Stop rec</b> or close the mirror window (do not force-kill); check the Live output panel for the reason.</li>
</ul>
</body></html>";
        }
    }
}
