using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

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

    internal Overlay(Screen screen, Color color, float brightness, bool banner)
    {
        this.color = color;
        this.brightness = brightness;
        this.banner = banner;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        Bounds = screen.Bounds;
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
        DrawLayer();
        if (!Native.SetWindowDisplayAffinity(Handle, Native.WdaExcludeFromCapture))
            MessageBox.Show("边缘光的截图排除未启用，错误码：" + Marshal.GetLastWin32Error(), "Miu AI");
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

    private static Bitmap RenderLayer(int width, int height, Color color, float brightness, bool banner, float dpiScale)
    {
        Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        BitmapData pixels = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        try
        {
            // A narrow top glow and quieter side/bottom halos fade continuously into the desktop.
            int radius = (int)Math.Ceiling(86 * dpiScale);
            byte[] topAlpha = new byte[radius], sideAlpha = new byte[radius], bottomAlpha = new byte[radius];
            for (int d = 0; d < radius; d++)
            {
                double logicalDistance = d / dpiScale;
                double distanceSquared = logicalDistance * logicalDistance;
                topAlpha[d] = (byte)(brightness * (80 * Math.Exp(-distanceSquared / 50.0) + 50 * Math.Exp(-distanceSquared / 1250.0)));
                sideAlpha[d] = (byte)(brightness * (18 * Math.Exp(-distanceSquared / 128.0) + 12 * Math.Exp(-distanceSquared / 1058.0)));
                bottomAlpha[d] = (byte)(brightness * (14 * Math.Exp(-distanceSquared / 128.0) + 8 * Math.Exp(-distanceSquared / 1058.0)));
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
                        byte a = (byte)Math.Min(255, top + side + bottom);
                        if (a == 0) continue;
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
                Rectangle r = new Rectangle(((int)Math.Round(width / dpiScale) - 390) / 2, 18, 390, 44);
                for (int i = 10; i >= 1; i--)
                {
                    Rectangle glow = Rectangle.Inflate(r, i, i / 2);
                    using (GraphicsPath path = Pill(glow, 14 + i / 2))
                    using (Pen pen = new Pen(Color.FromArgb((int)(brightness * 80 / i), color), 2))
                        g.DrawPath(pen, path);
                }
                using (GraphicsPath path = Pill(r, 12))
                using (Brush fill = new SolidBrush(Color.FromArgb(225, 4, 112, 43)))
                using (Pen rim = new Pen(Color.FromArgb(110, color), 1))
                {
                    g.FillPath(fill, path);
                    g.DrawPath(rim, path);
                }
                using (Font font = new Font("Segoe UI", 18, FontStyle.Bold, GraphicsUnit.Pixel))
                using (Brush ink = new SolidBrush(Color.White))
                using (StringFormat format = new StringFormat())
                {
                    format.Alignment = StringAlignment.Center;
                    format.LineAlignment = StringAlignment.Center;
                    g.DrawString("Miu AI is using your computer", font, ink, r, format);
                }
            }
        }
        return bitmap;
    }

    internal static void SavePreview(string path, Color color, float brightness)
    {
        string fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath));
        using (Bitmap preview = new Bitmap(1280, 720))
        using (Bitmap layer = RenderLayer(1280, 720, color, brightness, true, 1f))
        using (Graphics g = Graphics.FromImage(preview))
        {
            using (LinearGradientBrush background = new LinearGradientBrush(
                new Rectangle(0, 0, 1280, 720), Color.FromArgb(12, 20, 27), Color.FromArgb(30, 39, 48), 90f))
                g.FillRectangle(background, 0, 0, 1280, 720);
            g.DrawImageUnscaled(layer, 0, 0);
            preview.Save(fullPath, ImageFormat.Png);
        }
    }

    private void DrawLayer()
    {
        using (Bitmap bitmap = RenderLayer(Width, Height, color, brightness, banner, Math.Max(1f, Native.GetDpiForWindow(Handle) / 96f)))
        {
            IntPtr screenDc = Native.GetDC(IntPtr.Zero);
            IntPtr memoryDc = Native.CreateCompatibleDC(screenDc);
            IntPtr hBitmap = bitmap.GetHbitmap(Color.FromArgb(0));
            IntPtr old = Native.SelectObject(memoryDc, hBitmap);
            Native.Point position = new Native.Point(Left, Top);
            Native.Point source = new Native.Point(0, 0);
            Native.Size size = new Native.Size(Width, Height);
            Native.Blend blend = new Native.Blend { Op = 0, Flags = 0, Alpha = 255, Format = 1 };
            bool updated = Native.UpdateLayeredWindow(Handle, screenDc, ref position, ref size, memoryDc, ref source, 0, ref blend, 2);
            Native.SelectObject(memoryDc, old);
            Native.DeleteObject(hBitmap);
            Native.DeleteDC(memoryDc);
            Native.ReleaseDC(IntPtr.Zero, screenDc);
            if (!updated) throw new InvalidOperationException("UpdateLayeredWindow: " + Marshal.GetLastWin32Error());
        }
    }
}

internal sealed class OverlayApp : ApplicationContext
{
    private readonly Overlay[] windows;
    private readonly NotifyIcon tray;
    private readonly string verifyDirectory;
    private readonly Timer demoTimer;
    private readonly Timer parentTimer;
    private readonly Process parentProcess;
    private bool exiting;

    internal OverlayApp(Color color, float brightness, string verifyDirectory, int demoSeconds, bool showTray, int parentPid)
    {
        this.verifyDirectory = verifyDirectory;
        Screen[] screens = Screen.AllScreens;
        windows = new Overlay[screens.Length];
        for (int i = 0; i < screens.Length; i++)
        {
            windows[i] = new Overlay(screens[i], color, brightness, screens[i].Primary);
            windows[i].Show();
        }
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

    private void Exit()
    {
        if (exiting) return;
        exiting = true;
        if (demoTimer != null) demoTimer.Dispose();
        if (parentTimer != null) parentTimer.Dispose();
        if (parentProcess != null) parentProcess.Dispose();
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        foreach (Overlay window in windows) window.Close();
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
            System.Threading.Thread.Sleep(200);
            using (Bitmap included = Capture(primary))
            {
                bool affinity = true;
                foreach (Overlay window in windows)
                    affinity &= Native.SetWindowDisplayAffinity(window.Handle, Native.WdaExcludeFromCapture);
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
    [STAThread]
    private static void Main(string[] args)
    {
        Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); // Per-monitor V2, before WinForms queries screens.
        Color color = Color.FromArgb(0, 255, 100);
        float brightness = 1f;
        string verify = null;
        string preview = null;
        int demoSeconds = 0;
        int parentPid = 0;
        bool noTray = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--color" && ++i < args.Length) color = ColorTranslator.FromHtml(args[i]);
            else if (args[i] == "--brightness" && ++i < args.Length)
            {
                int percent = int.Parse(args[i]);
                if (percent < 0 || percent > 100) throw new ArgumentOutOfRangeException("brightness");
                brightness = percent / 100f;
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
            else throw new ArgumentException("Usage: MiuOverlay.exe [--color #RRGGBB] [--brightness 0..100] [--verify directory | --preview file.png] [--demo-seconds 1..3600] [--no-tray] [--parent-pid N]");
        }
        if (preview != null) { Overlay.SavePreview(preview, color, brightness); return; }
        Application.EnableVisualStyles();
        bool created;
        using (var mutex = new System.Threading.Mutex(true, @"Local\MiuAIOverlay", out created))
        {
            if (!created) return;
            try { Application.Run(new OverlayApp(color, brightness, verify, demoSeconds, !noTray, parentPid)); }
            finally { mutex.ReleaseMutex(); }
        }
    }
}
