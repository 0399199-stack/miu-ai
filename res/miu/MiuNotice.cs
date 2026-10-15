using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class NoticeContent
{
    internal string Title;
    internal string Text;
    internal int Seconds;
    internal bool Sound;
    internal Color TextColor = Color.FromArgb(28, 39, 64);

    internal static NoticeContent Read(Stream input)
    {
        const int limit = 24 * 1024;
        byte[] bytes = new byte[limit];
        int length = 0;
        int value;
        while ((value = input.ReadByte()) != -1 && value != '\n')
        {
            if (length == limit) throw new InvalidDataException();
            bytes[length++] = (byte)value;
        }
        string json = new UTF8Encoding(false, true).GetString(bytes, 0, length);
        JavaScriptSerializer serializer = new JavaScriptSerializer();
        serializer.MaxJsonLength = limit;
        serializer.RecursionLimit = 8;
        Dictionary<string, object> data = serializer.DeserializeObject(json) as Dictionary<string, object>;
        object title, text, seconds, sound;
        if (data == null || !data.TryGetValue("title", out title) || !(title is string) ||
            !data.TryGetValue("text", out text) || !(text is string) ||
            !data.TryGetValue("seconds", out seconds) || !(seconds is int) ||
            !data.TryGetValue("sound", out sound) || !(sound is bool))
            throw new InvalidDataException();
        ValidateCharacters((string)title, false);
        ValidateCharacters((string)text, true);
        string cleanTitle = ((string)title).Trim();
        string cleanText = ((string)text).Trim();
        if (cleanTitle.Length < 1 || cleanTitle.Length > 60 ||
            cleanText.Length < 1 || cleanText.Length > 1200 || (int)seconds < 1 || (int)seconds > 300)
            throw new InvalidDataException();
        Color textColor = Color.FromArgb(28, 39, 64);
        object colorValue;
        if (data.TryGetValue("textColor", out colorValue))
        {
            string hex = colorValue as string;
            if (hex == null || hex.Length != 7 || hex[0] != '#') throw new InvalidDataException();
            for (int i = 1; i < hex.Length; i++)
                if (!Uri.IsHexDigit(hex[i])) throw new InvalidDataException();
            textColor = Color.FromArgb(255, Convert.ToInt32(hex.Substring(1, 2), 16),
                Convert.ToInt32(hex.Substring(3, 2), 16), Convert.ToInt32(hex.Substring(5, 2), 16));
        }
        return new NoticeContent { Title = cleanTitle, Text = cleanText, Seconds = (int)seconds, Sound = (bool)sound, TextColor = textColor };
    }

    private static void ValidateCharacters(string value, bool multiline)
    {
        foreach (char character in value)
        {
            if ((!multiline && (character == '\u2028' || character == '\u2029')) ||
                (char.IsControl(character) && !(multiline && (character == '\r' || character == '\n' || character == '\t'))))
                throw new InvalidDataException();
        }
    }
}

internal sealed class NoticeWindow : Form
{
    private readonly NoticeContent content;
    private readonly Stopwatch elapsed = new Stopwatch();
    private readonly Timer timer = new Timer();
    private readonly Label countdown = new Label();
    private readonly Label title = new Label();
    private readonly RichTextBox body = new RichTextBox();
    private readonly Button acknowledge = new Button();
    private readonly Button close = new Button();
    private readonly Label brand = new Label();
    private float scale;
    private int secondsShown = -1;
    private int dividerY;

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

    internal NoticeWindow(NoticeContent content)
    {
        this.content = content;
        Text = "Miu AI · " + content.Title;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
        TopMost = true;
        ShowInTaskbar = true;
        BackColor = Color.FromArgb(247, 249, 254);
        ForeColor = Color.FromArgb(28, 39, 64);
        DoubleBuffered = true;
        Rectangle area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(area.Left + area.Width / 2, area.Top + area.Height / 2);
        using (Graphics graphics = CreateGraphics()) scale = graphics.DpiX / 96f;

        brand.Text = "MIU AI  /  消息";
        brand.Font = new Font("Segoe UI", 10f, FontStyle.Bold);
        brand.ForeColor = Color.FromArgb(64, 112, 231);
        brand.AutoSize = false;
        brand.TextAlign = ContentAlignment.MiddleLeft;
        brand.MouseDown += DragWindow;
        title.Text = content.Title;
        title.Font = new Font("Microsoft YaHei UI", 16f, FontStyle.Bold);
        title.ForeColor = content.TextColor;
        title.UseMnemonic = false;
        title.MouseDown += DragWindow;
        body.Font = new Font("Microsoft YaHei UI", 11f);
        body.Text = content.Text;
        body.ReadOnly = true;
        body.DetectUrls = false;
        body.BorderStyle = BorderStyle.None;
        body.BackColor = BackColor;
        body.ForeColor = content.TextColor;
        body.ScrollBars = RichTextBoxScrollBars.Vertical;
        body.WordWrap = true;
        body.ShortcutsEnabled = true;
        body.AccessibleName = "消息正文，可选择和复制";
        body.TabIndex = 0;
        countdown.Font = new Font("Microsoft YaHei UI", 9f);
        countdown.ForeColor = Color.FromArgb(105, 116, 139);
        countdown.TextAlign = ContentAlignment.MiddleLeft;
        countdown.AutoSize = false;
        ConfigureButton(close, "×", Color.Transparent, ForeColor);
        close.Font = new Font("Segoe UI", 20f);
        close.AccessibleName = "关闭消息";
        close.TabIndex = 2;
        ConfigureButton(acknowledge, "我知道了", Color.FromArgb(62, 112, 235), Color.White);
        acknowledge.TabIndex = 1;
        close.Click += delegate { Close(); };
        acknowledge.Click += delegate { Close(); };
        MouseDown += DragWindow;
        Controls.AddRange(new Control[] { brand, title, body, countdown, acknowledge, close });
        SizeToContent(area);
        LayoutContent();
        UpdateCountdown();
        timer.Interval = 100;
        timer.Tick += delegate
        {
            if (elapsed.Elapsed.TotalSeconds >= content.Seconds) Close();
            else UpdateCountdown();
        };
    }

    private int Px(float value) { return Math.Max(1, (int)Math.Round(value * scale)); }

    private void SizeToContent(Rectangle area)
    {
        int margin = Px(24);
        int availableWidth = Math.Max(1, area.Width - Px(24));
        int maximumWidth = Math.Min(Px(620), availableWidth);
        int titleWidth = TextRenderer.MeasureText(content.Title, title.Font,
            Size.Empty, TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine).Width;
        int textWidth = TextRenderer.MeasureText(content.Text, body.Font,
            Size.Empty, TextFormatFlags.NoPrefix).Width + Px(8);
        int width = Math.Min(maximumWidth, Math.Max(Px(360), Math.Max(titleWidth, textWidth) + margin * 2));
        int innerWidth = Math.Max(1, width - margin * 2);
        int titleHeight = MeasureTitleHeight(innerWidth);
        int textHeight = TextRenderer.MeasureText(content.Text, body.Font,
            new Size(Math.Max(1, innerWidth - Px(8)), int.MaxValue),
            TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix | TextFormatFlags.TextBoxControl).Height + Px(8);
        int height = Px(58) + titleHeight + Px(12) + Math.Max(Px(28), textHeight) + Px(82);
        ClientSize = new Size(width, Math.Min(height, Math.Min(Px(560), Math.Max(1, area.Height - Px(24)))));
        Location = new Point(area.Left + (area.Width - Width) / 2, area.Top + (area.Height - Height) / 2);
    }

    private int MeasureTitleHeight(int width)
    {
        return TextRenderer.MeasureText(content.Title, title.Font,
            new Size(Math.Max(1, width), int.MaxValue), TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix).Height + Px(4);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= 0x00000008; // WS_EX_TOPMOST at native window creation.
            return parameters;
        }
    }

    private static void ConfigureButton(Button button, string text, Color background, Color foreground)
    {
        button.Text = text;
        button.Font = new Font("Microsoft YaHei UI", 10f);
        button.FlatStyle = FlatStyle.Flat;
        button.FlatAppearance.BorderSize = 0;
        button.BackColor = background;
        button.ForeColor = foreground;
        button.Cursor = Cursors.Hand;
        button.UseVisualStyleBackColor = false;
    }

    private void LayoutContent()
    {
        int margin = Px(24);
        int innerWidth = ClientSize.Width - margin * 2;
        brand.SetBounds(margin, Px(14), innerWidth - Px(40), Px(28));
        close.SetBounds(ClientSize.Width - margin - Px(30), Px(9), Px(34), Px(34));
        int titleHeight = Math.Min(MeasureTitleHeight(innerWidth), Math.Max(Px(30), ClientSize.Height / 3));
        title.SetBounds(margin, Px(58), innerWidth, titleHeight);
        int footerTop = ClientSize.Height - Px(62);
        dividerY = footerTop - Px(10);
        int bodyTop = title.Bottom + Px(12);
        body.SetBounds(margin, bodyTop, innerWidth, Math.Max(Px(20), dividerY - bodyTop - Px(10)));
        countdown.SetBounds(margin, footerTop, innerWidth - Px(120), Px(42));
        acknowledge.SetBounds(ClientSize.Width - margin - Px(108), footerTop, Px(108), Px(42));
    }

    private void DragWindow(object sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        ReleaseCapture();
        SendMessage(Handle, 0x00A1, new IntPtr(2), IntPtr.Zero);
    }

    private void UpdateCountdown()
    {
        int remaining = Math.Max(0, content.Seconds - (int)elapsed.Elapsed.TotalSeconds);
        if (remaining == secondsShown) return;
        secondsShown = remaining;
        countdown.Text = remaining + " 秒后自动关闭 · Esc 关闭";
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        elapsed.Start();
        timer.Start();
        // The controller only acknowledges display once the native window is shown.
        Console.Out.WriteLine("SHOWN");
        Console.Out.Flush();
        if (content.Sound)
        {
            try { SystemSounds.Asterisk.Play(); }
            catch { Console.Error.WriteLine("NOTICE_SOUND_UNAVAILABLE"); }
        }
    }

    protected override bool ProcessCmdKey(ref Message message, Keys keyData)
    {
        if (keyData == Keys.Escape) { Close(); return true; }
        return base.ProcessCmdKey(ref message, keyData);
    }

    private static GraphicsPath RoundRectangle(Rectangle bounds, int radius)
    {
        GraphicsPath path = new GraphicsPath();
        int diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
        using (GraphicsPath path = RoundRectangle(new Rectangle(0, 0, Width, Height), Px(18)))
        {
            Region previous = Region;
            Region = new Region(path);
            if (previous != null) previous.Dispose();
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath border = RoundRectangle(new Rectangle(0, 0, Width - 1, Height - 1), Px(18)))
        using (Pen pen = new Pen(Color.FromArgb(205, 215, 235), Px(1))) e.Graphics.DrawPath(pen, border);
        using (Pen pen = new Pen(Color.FromArgb(223, 230, 242)))
            e.Graphics.DrawLine(pen, Px(24), dividerY, Width - Px(24), dividerY);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) timer.Dispose();
        base.Dispose(disposing);
    }
}

internal static class Program
{
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--check") return 0;
        try
        {
            if (args.Length != 0) throw new InvalidDataException();
            NoticeContent content = NoticeContent.Read(Console.OpenStandardInput());
            Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true });
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); }
            catch (EntryPointNotFoundException) { SetProcessDPIAware(); }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            using (NoticeWindow window = new NoticeWindow(content)) Application.Run(window);
            return 0;
        }
        catch
        {
            Console.Error.WriteLine("NOTICE_FAILED");
            return 1;
        }
    }
}
