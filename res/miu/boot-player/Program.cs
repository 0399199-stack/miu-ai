using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Controls;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

internal static class Program
{
    [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }
            CoreWebView2Environment.GetAvailableBrowserVersionString();
            if (!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web", "index.html"))) return 1;
            if (args.Length == 1 && args[0] == "--check") return 0;
            string color = args.Length == 2 && args[0] == "--color" ? args[1] : "#48AAFF";
            if (color.Length != 7 || !Regex.IsMatch(color, "^#[0-9a-fA-F]{6}$")) return 2;
            bool created;
            using (var mutex = new Mutex(true, "Local\\MiuAI.Boot.Player", out created))
            {
                if (!created) return 3;
                return new Application().Run(new BootWindow(color));
            }
        }
        catch (Exception)
        {
            Console.Error.WriteLine("Miu boot player unavailable. Check WebView2 Runtime and local assets.");
            return 1;
        }
    }
}

internal sealed class BootWindow : Window
{
    private readonly WebView2CompositionControl view = new WebView2CompositionControl();
    private readonly string color;
    private dynamic narrator;
    private bool allowClose;
    private readonly MediaPlayer music = new MediaPlayer();
    private readonly MediaPlayer cue = new MediaPlayer();
    private static readonly Dictionary<string, string> narration = new Dictionary<string, string> {
        { "voice:access", "Access permission required." },
        { "voice:identity", "Identity verification." },
        { "voice:request", "Access request received." },
        { "voice:read", "Reading permissions." },
        { "voice:complete", "Read complete." },
        { "voice:verified", "Verification complete." },
        { "voice:ready", "Miu AI is ready. Let us begin your day." }
    };
    private readonly Border backdrop = new Border { Background = Brushes.Black, IsHitTestVisible = false };
    private readonly DispatcherTimer watchdog = new DispatcherTimer { Interval = TimeSpan.FromSeconds(65) };
    private const string Origin = "https://miu-boot.local/";

    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RectNative rect);
    [StructLayout(LayoutKind.Sequential)] private struct RectNative { public int Left, Top, Right, Bottom; }

    internal BootWindow(string color)
    {
        this.color = color;
        Title = "Miu AI 开机欢迎";
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        Cursor = Cursors.None;
        var root = new Grid();
        root.Children.Add(backdrop);
        root.Children.Add(view);
        Content = root;
        view.DefaultBackgroundColor = System.Drawing.Color.Transparent;
        view.AllowExternalDrop = false;
        Closing += (_, e) => { if (!allowClose) e.Cancel = true; };
        Application.Current.SessionEnding += (_, e) => { allowClose = true; };
        SourceInitialized += (_, __) =>
        {
            var bounds = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            var hwnd = new WindowInteropHelper(this).Handle;
            var source = PresentationSource.FromVisual(this);
            var logical = source.CompositionTarget.TransformFromDevice.Transform(new Point(bounds.Width, bounds.Height));
            Width = logical.X;
            Height = logical.Y;
            SetWindowPos(hwnd, new IntPtr(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0040);
            RectNative actual;
            if (!GetWindowRect(hwnd, out actual) || actual.Right - actual.Left != bounds.Width || actual.Bottom - actual.Top != bounds.Height)
                throw new InvalidOperationException("Fullscreen bounds mismatch");
        };
        watchdog.Tick += (_, __) => Stop("timeout");
        Closed += (_, __) => {
            watchdog.Stop();
            music.Close();
            cue.Close();
            try { if (narrator != null) narrator.Speak("", 3); } catch (Exception) { }
            view.Dispose();
        };
        Loaded += async (_, __) =>
        {
            watchdog.Start();
            try
            {
                string folder = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "web");
                if (!File.Exists(Path.Combine(folder, "index.html"))) throw new FileNotFoundException();
                music.MediaFailed += (_, e) => Console.Error.WriteLine("Miu boot: music unavailable");
                cue.MediaFailed += (_, e) => Console.Error.WriteLine("Miu boot: sound effect unavailable");
                music.MediaEnded += (_, e) => { music.Position = TimeSpan.Zero; music.Play(); };
                music.Volume = .35;
                cue.Volume = .65;
                music.Open(new Uri(Path.Combine(folder, "music.wav")));
                cue.Open(new Uri(Path.Combine(folder, "cue.wav")));
                string profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MiuAI", "BootWebView");
                var options = new CoreWebView2EnvironmentOptions("--autoplay-policy=no-user-gesture-required");
                var environment = await CoreWebView2Environment.CreateAsync(null, profile, options);
                await view.EnsureCoreWebView2Async(environment);
                var core = view.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.AreBrowserAcceleratorKeysEnabled = false;
                core.Settings.IsStatusBarEnabled = false;
                core.SetVirtualHostNameToFolderMapping("miu-boot.local", folder, CoreWebView2HostResourceAccessKind.DenyCors);
                core.NavigationStarting += (_, e) => { e.Cancel = e.Uri != Origin + "index.html"; };
                core.NewWindowRequested += (_, e) => { e.Handled = true; };
                core.DownloadStarting += (_, e) => { e.Cancel = true; };
                core.PermissionRequested += (_, e) => { e.State = CoreWebView2PermissionState.Deny; };
                core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
                core.WebResourceRequested += (_, e) =>
                {
                    if (!e.Request.Uri.StartsWith(Origin, StringComparison.Ordinal))
                        e.Response = environment.CreateWebResourceResponse(null, 403, "Blocked", "");
                };
                core.ProcessFailed += (_, e) =>
                {
                    Stop("renderer failure: " + e.ProcessFailedKind);
                };
                core.WebMessageReceived += (_, e) =>
                {
                    if (e.Source != Origin + "index.html") return;
                    string message = e.TryGetWebMessageAsString();
                    if (narration.TryGetValue(message, out var spoken))
                    {
                        cue.Position = TimeSpan.Zero;
                        cue.Play();
                        try
                        {
                            if (narrator == null)
                            {
                                var type = Type.GetTypeFromProgID("SAPI.SpVoice");
                                if (type != null)
                                {
                                    narrator = Activator.CreateInstance(type);
                                    var voices = narrator.GetVoices("Language=409");
                                    if (voices.Count > 0) narrator.Voice = voices.Item(0);
                                }
                            }
                            if (narrator != null) {
                                narrator.Speak(spoken, 1);
                                Console.Error.WriteLine("Miu boot: narration " + message.Substring(6));
                            }
                        }
                        catch (Exception) { Console.Error.WriteLine("Miu boot: narrator unavailable"); }
                        return;
                    }
                    if (message == "started") { music.Play(); Console.WriteLine("STARTED"); Console.Out.Flush(); }
                    else if (message == "handoff")
                    {
                        view.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromSeconds(1.4)) {
                            EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseInOut }
                        });
                        // Reveal the desktop and its existing glow after the new finale.
                        var mask = new RadialGradientBrush(Colors.White, Colors.White) { RadiusX = .72, RadiusY = .72 };
                        backdrop.OpacityMask = mask;
                        for (int i = 0; i < mask.GradientStops.Count; i++)
                        {
                            mask.GradientStops[i].BeginAnimation(GradientStop.ColorProperty,
                                new ColorAnimation(Colors.White, Colors.Transparent, TimeSpan.FromSeconds(1.45)) {
                                    BeginTime = TimeSpan.FromSeconds(i * .12),
                                    EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseInOut }
                                });
                        }
                    }
                    else if (message == "finished") Stop("finished");
                };
                await core.AddScriptToExecuteOnDocumentCreatedAsync("window.MIU_BOOT_COLOR='" + color + "';");
                core.Navigate(Origin + "index.html");
                view.Focus();
            }
            catch (Exception)
            {
                Console.Error.WriteLine("Miu boot player could not start.");
                Stop("initialization failure");
            }
        };
    }

    private void Stop(string reason)
    {
        allowClose = true;
        try { Console.Error.WriteLine("Miu boot: " + reason); }
        catch (IOException) { /* The requesting app may already have closed its pipe. */ }
        Close();
    }
}
