using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Native
{
    internal const uint WdaExcludeFromCapture = 0x11;

    [StructLayout(LayoutKind.Sequential)] internal struct Point { internal int X, Y; internal Point(int x, int y) { X = x; Y = y; } }
    [StructLayout(LayoutKind.Sequential)] internal struct Size { internal int Width, Height; internal Size(int w, int h) { Width = w; Height = h; } }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] internal struct Blend { internal byte Op, Flags, Alpha, Format; }

    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetWindowDisplayAffinity(IntPtr window, uint affinity);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] internal static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] internal static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool UpdateLayeredWindow(IntPtr window, IntPtr dst, ref Point position, ref Size size, IntPtr src, ref Point source, int key, ref Blend blend, int flags);
}

internal sealed class Overlay : Form
{
    private readonly Color color;
    private readonly float brightness;
    private readonly bool banner;
    private readonly string text;
    private readonly bool accent;
    private readonly Screen screen;
    private IntPtr memoryDc;
    private IntPtr layerBitmap;
    private IntPtr previousBitmap;

    internal Overlay(Screen screen, Color color, float brightness, bool banner, bool accent, string text)
    {
        this.screen = screen;
        this.color = color;
        this.brightness = brightness;
        this.banner = banner;
        this.text = text;
        this.accent = accent;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        Bounds = accent ? new Rectangle(screen.Bounds.Left - 160, screen.Bounds.Top - 160, 320, 320) : screen.Bounds;
        TopMost = true;
        ShowInTaskbar = false;
    }

    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams p = base.CreateParams;
            p.ExStyle |= 0x00080000 | 0x00000020 | 0x00000080 | 0x08000000; // layered, click-through, tool, no activate
            return p;
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        using (Bitmap bitmap = accent ? RenderAccent(color, brightness) : RenderLayer(Width, Height, color, brightness, banner, Math.Max(1f, Native.GetDpiForWindow(Handle) / 96f), text))
        {
            IntPtr screenDc = Native.GetDC(IntPtr.Zero);
            try
            {
                memoryDc = Native.CreateCompatibleDC(screenDc);
                if (memoryDc == IntPtr.Zero) throw new InvalidOperationException("CreateCompatibleDC: " + Marshal.GetLastWin32Error());
                layerBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
                previousBitmap = Native.SelectObject(memoryDc, layerBitmap);
                if (previousBitmap == IntPtr.Zero) throw new InvalidOperationException("SelectObject: " + Marshal.GetLastWin32Error());
            }
            catch
            {
                if (layerBitmap != IntPtr.Zero) Native.DeleteObject(layerBitmap);
                if (memoryDc != IntPtr.Zero) Native.DeleteDC(memoryDc);
                memoryDc = IntPtr.Zero;
                layerBitmap = IntPtr.Zero;
                throw;
            }
            finally { Native.ReleaseDC(IntPtr.Zero, screenDc); }
        }
        UpdateLayer(255);
        if (!Native.SetWindowDisplayAffinity(Handle, Native.WdaExcludeFromCapture))
            MessageBox.Show("边缘光的截图排除未启用，错误码：" + Marshal.GetLastWin32Error(), "Miu AI");
    }

    internal void MoveAccent(double phase)
    {
        if (!accent) return;
        Rectangle bounds = screen.Bounds;
        double edge = phase * 2 * (bounds.Width + bounds.Height);
        int x, y;
        if (edge < bounds.Width) { x = bounds.Left + (int)edge; y = bounds.Top; }
        else if ((edge -= bounds.Width) < bounds.Height) { x = bounds.Right; y = bounds.Top + (int)edge; }
        else if ((edge -= bounds.Height) < bounds.Width) { x = bounds.Right - (int)edge; y = bounds.Bottom; }
        else { edge -= bounds.Width; x = bounds.Left; y = bounds.Bottom - (int)edge; }
        Location = new Point(x - Width / 2, y - Height / 2);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        if (memoryDc != IntPtr.Zero)
        {
            Native.SelectObject(memoryDc, previousBitmap);
            Native.DeleteObject(layerBitmap);
            Native.DeleteDC(memoryDc);
            memoryDc = IntPtr.Zero;
        }
        base.OnFormClosed(e);
    }

    private static GraphicsPath Pill(Rectangle r, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int d = radius * 2;
        path.AddArc(r.Left, r.Top, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Top, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Bitmap RenderLayer(int width, int height, Color color, float brightness, bool banner, float dpiScale, string text)
    {
        Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        BitmapData pixels = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            // Keep all four edges visible while fading the halos into the desktop.
            int radius = (int)Math.Ceiling(176 * dpiScale);
            byte[] topAlpha = new byte[radius], sideAlpha = new byte[radius], bottomAlpha = new byte[radius];
            for (int d = 0; d < radius; d++)
            {
                double logicalDistance = d / dpiScale;
                double distanceSquared = logicalDistance * logicalDistance;
                topAlpha[d] = (byte)Math.Min(255, brightness * (160 * Math.Exp(-distanceSquared / 80.0) + 100 * Math.Exp(-distanceSquared / 2200.0)));
                sideAlpha[d] = (byte)Math.Min(255, brightness * (68 * Math.Exp(-distanceSquared / 1100.0) + 60 * Math.Exp(-distanceSquared / 7600.0)));
                bottomAlpha[d] = (byte)Math.Min(255, brightness * (64 * Math.Exp(-distanceSquared / 1100.0) + 54 * Math.Exp(-distanceSquared / 7600.0)));
            }
            unsafe
            {
                byte* origin = (byte*)pixels.Scan0;
                for (int y = 0; y < height; y++)
                {
                    int top = y < radius ? topAlpha[y] : 0;
                    int bottomDistance = height - 1 - y;
                    int bottom = bottomDistance < radius ? bottomAlpha[bottomDistance] : 0;
                    byte* row = origin + y * pixels.Stride;
                    for (int x = 0; x < width; x++)
                    {
                        int sideDistance = Math.Min(x, width - 1 - x);
                        int side = sideDistance < radius ? sideAlpha[sideDistance] : 0;
                        int combined = Math.Min(255, top + side + bottom);
                        if (combined == 0) continue;
                        byte a = (byte)combined;
                        byte* pixel = row + x * 4;
                        pixel[0] = (byte)(color.B * a / 255);
                        pixel[1] = (byte)(color.G * a / 255);
                        pixel[2] = (byte)(color.R * a / 255);
                        pixel[3] = a;
                    }
                }
            }
        }
        finally { bitmap.UnlockBits(pixels); }
        using (Graphics g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.ScaleTransform(dpiScale, dpiScale);
            if (banner)
            {
                using (Font font = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel))
                {
                    int logicalWidth = (int)Math.Round(width / dpiScale);
                    int desiredWidth = (int)Math.Ceiling(g.MeasureString(text, font).Width) + 44;
                    int pillWidth = Math.Min(Math.Max(80, logicalWidth - 32), Math.Max(160, desiredWidth));
                    Rectangle r = new Rectangle((logicalWidth - pillWidth) / 2, 18, pillWidth, 44);
                    for (int i = 10; i >= 1; i--)
                    {
                        Rectangle glow = Rectangle.Inflate(r, i, i / 2);
                        using (GraphicsPath path = Pill(glow, 14 + i / 2))
                        using (Pen pen = new Pen(Color.FromArgb((int)(brightness * 80 / i), color), 2))
                            g.DrawPath(pen, path);
                    }
                    using (GraphicsPath path = Pill(r, 12))
                    using (Brush fill = new SolidBrush(Color.FromArgb(230,
                        20 + color.R * 42 / 100, 20 + color.G * 42 / 100, 20 + color.B * 42 / 100)))
                    using (Pen rim = new Pen(Color.FromArgb(110, color), 1))
                    {
                        g.FillPath(fill, path);
                        g.DrawPath(rim, path);
                    }
                    using (Brush ink = new SolidBrush(Color.White))
                    using (StringFormat format = new StringFormat())
                    {
                        format.Alignment = StringAlignment.Center;
                        format.LineAlignment = StringAlignment.Center;
                        format.FormatFlags = StringFormatFlags.NoWrap;
                        format.Trimming = StringTrimming.EllipsisCharacter;
                        g.DrawString(text, font, ink, Rectangle.Inflate(r, -14, 0), format);
                    }
                }
            }
        }
        return bitmap;
    }

    private static Bitmap RenderAccent(Color color, float brightness)
    {
        const int size = 320;
        Bitmap bitmap = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
        BitmapData pixels = bitmap.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            unsafe
            {
                byte* origin = (byte*)pixels.Scan0;
                for (int y = 0; y < size; y++)
                {
                    byte* row = origin + y * pixels.Stride;
                    for (int x = 0; x < size; x++)
                    {
                        double distanceSquared = (x - 160) * (x - 160) + (y - 160) * (y - 160);
                        byte a = (byte)Math.Min(255, brightness * (130 * Math.Exp(-distanceSquared / 1800.0) + 70 * Math.Exp(-distanceSquared / 10000.0)));
                        byte* pixel = row + x * 4;
                        pixel[0] = (byte)(color.B * a / 255);
                        pixel[1] = (byte)(color.G * a / 255);
                        pixel[2] = (byte)(color.R * a / 255);
                        pixel[3] = a;
                    }
                }
            }
        }
        finally { bitmap.UnlockBits(pixels); }
        return bitmap;
    }

    internal static void SavePreview(string path, Color color, float brightness, string text)
    {
        string fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath));
        using (Bitmap preview = new Bitmap(1280, 720))
        using (Bitmap layer = RenderLayer(1280, 720, color, brightness, true, 1f, text))
        using (Graphics g = Graphics.FromImage(preview))
        {
            using (LinearGradientBrush background = new LinearGradientBrush(
                new Rectangle(0, 0, 1280, 720), Color.FromArgb(12, 20, 27), Color.FromArgb(30, 39, 48), 90f))
                g.FillRectangle(background, 0, 0, 1280, 720);
            g.DrawImageUnscaled(layer, 0, 0);
            preview.Save(fullPath, ImageFormat.Png);
        }
    }

    internal void UpdateLayer(byte alpha)
    {
        IntPtr screenDc = Native.GetDC(IntPtr.Zero);
        Native.Point position = new Native.Point(Left, Top);
        Native.Point source = new Native.Point(0, 0);
        Native.Size size = new Native.Size(Width, Height);
        Native.Blend blend = new Native.Blend { Op = 0, Flags = 0, Alpha = alpha, Format = 1 };
        bool updated = Native.UpdateLayeredWindow(Handle, screenDc, ref position, ref size, memoryDc, ref source, 0, ref blend, 2);
        Native.ReleaseDC(IntPtr.Zero, screenDc);
        if (!updated) throw new InvalidOperationException("UpdateLayeredWindow: " + Marshal.GetLastWin32Error());
    }
}

internal sealed class OverlayApp : ApplicationContext
{
    private Overlay[] windows;
    private Overlay[] accents;
    private readonly NotifyIcon tray;
    private readonly string verifyDirectory;
    private readonly Timer demoTimer;
    private readonly Timer parentTimer;
    private readonly Timer animationTimer;
    private readonly Process parentProcess;
    private readonly Color color;
    private readonly float brightness;
    private readonly string effect;
    private readonly string text;
    private readonly int periodMs;
    private bool exiting;

    internal OverlayApp(Color color, float brightness, string effect, int periodMs, string verifyDirectory, int demoSeconds, bool showTray, int parentPid, string text)
    {
        this.color = color;
        this.brightness = brightness;
        this.effect = effect;
        this.text = text;
        this.periodMs = periodMs;
        this.verifyDirectory = verifyDirectory;
        RebuildWindows();
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        Stopwatch animationClock = Stopwatch.StartNew();
        byte lastAlpha = 255;
        animationTimer = new Timer { Interval = effect == "marquee" ? 100 : 80 };
        animationTimer.Tick += delegate
        {
            double phase = (animationClock.Elapsed.TotalMilliseconds % periodMs) / periodMs;
            if (effect == "marquee")
            {
                foreach (Overlay accent in accents) accent.MoveAccent(phase);
                return;
            }
            double wave = (1 + Math.Cos(phase * 2 * Math.PI)) / 2;
            double strength = effect == "steady" ? 1
                : effect == "blink" ? 0.42 + 0.58 * wave * wave
                : effect == "heartbeat" ? 0.48 + 0.52 * Math.Min(1,
                    Math.Exp(-Math.Pow((phase - 0.18) / 0.055, 2)) +
                    0.72 * Math.Exp(-Math.Pow((phase - 0.34) / 0.07, 2)))
                : 0.48 + 0.52 * wave;
            byte alpha = (byte)Math.Round(255 * strength);
            if (alpha == lastAlpha) return;
            lastAlpha = alpha;
            foreach (Overlay window in windows) window.UpdateLayer(alpha);
        };
        animationTimer.Start();
        if (showTray)
            tray = new NotifyIcon { Icon = SystemIcons.Application, Text = "Miu AI", Visible = true };
        if (parentPid > 0)
        {
            try { parentProcess = Process.GetProcessById(parentPid); }
            catch (ArgumentException) { }
            parentTimer = new Timer { Interval = 1000 };
            parentTimer.Tick += delegate { if (parentProcess == null || parentProcess.HasExited) Exit(); };
            parentTimer.Start();
        }
        if (demoSeconds > 0)
        {
            demoTimer = new Timer { Interval = demoSeconds * 1000 };
            demoTimer.Tick += delegate { demoTimer.Stop(); Exit(); };
            demoTimer.Start();
        }
        if (verifyDirectory != null)
        {
            Timer timer = new Timer { Interval = 700 };
            timer.Tick += delegate { timer.Stop(); timer.Dispose(); Verify(); };
            timer.Start();
        }
    }

    private void RebuildWindows()
    {
        if (windows != null)
            foreach (Overlay window in windows) window.Close();
        if (accents != null)
            foreach (Overlay accent in accents) accent.Close();
        Screen[] screens = Screen.AllScreens;
        windows = new Overlay[screens.Length];
        accents = effect == "marquee" ? new Overlay[screens.Length] : new Overlay[0];
        for (int i = 0; i < screens.Length; i++)
        {
            windows[i] = new Overlay(screens[i], color, brightness, screens[i].Primary, false, text);
            windows[i].Show();
            if (effect == "marquee")
            {
                accents[i] = new Overlay(screens[i], color, brightness, false, true, text);
                accents[i].Show();
            }
        }
    }

    private void OnDisplaySettingsChanged(object sender, EventArgs e)
    {
        if (exiting || windows.Length == 0) return;
        windows[0].BeginInvoke(new Action(RebuildWindows));
    }

    private void Exit()
    {
        if (exiting) return;
        exiting = true;
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        animationTimer.Dispose();
        if (demoTimer != null) demoTimer.Dispose();
        if (parentTimer != null) parentTimer.Dispose();
        if (parentProcess != null) parentProcess.Dispose();
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        foreach (Overlay window in windows) window.Close();
        foreach (Overlay accent in accents) accent.Close();
        ExitThread();
    }

    private Bitmap Capture(Screen screen)
    {
        Bitmap shot = new Bitmap(screen.Bounds.Width, screen.Bounds.Height);
        using (Graphics g = Graphics.FromImage(shot))
            g.CopyFromScreen(screen.Bounds.Location, Point.Empty, shot.Size);
        return shot;
    }

    private void Verify()
    {
        Directory.CreateDirectory(verifyDirectory);
        string report = Path.Combine(verifyDirectory, "verify.txt");
        try
        {
            Screen primary = Screen.PrimaryScreen;
            foreach (Overlay window in windows) Native.SetWindowDisplayAffinity(window.Handle, 0);
            foreach (Overlay accent in accents) Native.SetWindowDisplayAffinity(accent.Handle, 0);
            System.Threading.Thread.Sleep(200);
            using (Bitmap included = Capture(primary))
            {
                bool affinity = true;
                foreach (Overlay window in windows)
                    affinity &= Native.SetWindowDisplayAffinity(window.Handle, Native.WdaExcludeFromCapture);
                foreach (Overlay accent in accents)
                    affinity &= Native.SetWindowDisplayAffinity(accent.Handle, Native.WdaExcludeFromCapture);
                System.Threading.Thread.Sleep(200);
                using (Bitmap excluded = Capture(primary))
                {
                    int topChanged = 0, topSamples = 0, sideChanged = 0, sideSamples = 0, rightChanged = 0, rightSamples = 0, bottomChanged = 0, bottomSamples = 0;
                    for (int x = 100; x < included.Width - 100; x += 4)
                    {
                        Color a = included.GetPixel(x, 4), b = excluded.GetPixel(x, 4);
                        if (Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) > 40) topChanged++;
                        topSamples++;
                        a = included.GetPixel(x, included.Height - 5); b = excluded.GetPixel(x, excluded.Height - 5);
                        if (Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) > 8) bottomChanged++;
                        bottomSamples++;
                    }
                    for (int y = 100; y < included.Height - 100; y += 4)
                    {
                        Color a = included.GetPixel(4, y), b = excluded.GetPixel(4, y);
                        if (Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) > 8) sideChanged++;
                        sideSamples++;
                        a = included.GetPixel(included.Width - 5, y); b = excluded.GetPixel(excluded.Width - 5, y);
                        if (Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B) > 8) rightChanged++;
                        rightSamples++;
                    }
                    File.WriteAllText(report, "affinity=" + affinity + Environment.NewLine +
                        "overlay_bounds=" + windows[0].Bounds + Environment.NewLine +
                        "overlay_dpi=" + Native.GetDpiForWindow(windows[0].Handle) + Environment.NewLine +
                        "screen_bounds=" + primary.Bounds + Environment.NewLine +
                        "changed_top_samples=" + topChanged + "/" + topSamples + Environment.NewLine +
                        "changed_side_samples=" + sideChanged + "/" + sideSamples + Environment.NewLine +
                        "changed_right_samples=" + rightChanged + "/" + rightSamples + Environment.NewLine +
                        "changed_bottom_samples=" + bottomChanged + "/" + bottomSamples + Environment.NewLine +
                        "result=" + (affinity && topChanged > topSamples / 2 && sideChanged > sideSamples / 2 && rightChanged > rightSamples / 2
                            ? (bottomChanged > bottomSamples / 2 ? "PASS" : "PARTIAL") : "FAIL") + Environment.NewLine);
                }
            }
        }
        catch (Exception e) { File.WriteAllText(report, "result=ERROR" + Environment.NewLine + e); }
        Exit();
    }
}

internal static class Program
{
    private const float MaxGlowGain = 3f;

    [STAThread]
    private static void Main(string[] args)
    {
        Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); // Per-monitor V2, before WinForms queries screens.
        Color color = Color.FromArgb(141, 124, 247);
        float brightness = MaxGlowGain;
        string effect = "breathing";
        string text = "Miu AI is using your computer";
        int periodMs = 3000;
        string verify = null;
        string preview = null;
        int demoSeconds = 0;
        int parentPid = 0;
        bool noTray = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--color" && ++i < args.Length) color = ColorTranslator.FromHtml(args[i]);
            else if (args[i] == "--text" && ++i < args.Length) text = args[i];
            else if (args[i] == "--brightness" && ++i < args.Length)
            {
                int percent = int.Parse(args[i]);
                if (percent < 0 || percent > 100) throw new ArgumentOutOfRangeException("brightness");
                brightness = percent * MaxGlowGain / 100f;
            }
            else if (args[i] == "--period-ms" && ++i < args.Length)
            {
                periodMs = int.Parse(args[i]);
                if (periodMs < 1200 || periodMs > 10000) throw new ArgumentOutOfRangeException("period-ms");
            }
            else if (args[i] == "--effect" && ++i < args.Length)
            {
                effect = args[i];
                if (effect != "breathing" && effect != "steady" && effect != "blink" && effect != "marquee" && effect != "heartbeat")
                    throw new ArgumentException("effect");
            }
            else if (args[i] == "--verify" && ++i < args.Length) verify = Path.GetFullPath(args[i]);
            else if (args[i] == "--preview" && ++i < args.Length) preview = Path.GetFullPath(args[i]);
            else if (args[i] == "--demo-seconds" && ++i < args.Length)
            {
                demoSeconds = int.Parse(args[i]);
                if (demoSeconds < 1 || demoSeconds > 3600) throw new ArgumentOutOfRangeException("demo-seconds");
            }
            else if (args[i] == "--no-tray") noTray = true;
            else if (args[i] == "--parent-pid" && ++i < args.Length) parentPid = int.Parse(args[i]);
            else throw new ArgumentException("Usage: MiuOverlay.exe [--color #RRGGBB] [--text message] [--brightness 0..100] [--effect breathing|steady|blink|marquee|heartbeat] [--period-ms 1200..10000] [--verify directory | --preview file.png] [--demo-seconds 1..3600] [--no-tray] [--parent-pid N]");
        }
        if (String.IsNullOrWhiteSpace(text) || text.Length > 160 || Array.Exists(text.ToCharArray(), Char.IsControl)) throw new ArgumentException("text");
        if (preview != null) { Overlay.SavePreview(preview, color, brightness, text); return; }
        // Live overlays must belong to the tray; an accidental manual launch cannot outlive a session.
        if (parentPid <= 0 && verify == null && demoSeconds == 0) return;
        Application.EnableVisualStyles();
        bool created;
        using (var mutex = new System.Threading.Mutex(true, @"Local\MiuAIOverlay", out created))
        {
            if (!created) return;
            try { Application.Run(new OverlayApp(color, brightness, effect, periodMs, verify, demoSeconds, !noTray, parentPid, text)); }
            finally { mutex.ReleaseMutex(); }
        }
    }
}
