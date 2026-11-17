# Miu AI Windows welcome player

This version replaces the previous animation with an adaptation of
[dsh-startup-screen](https://github.com/6shenhonghong9/dsh-startup-screen),
revision `7f3d2837c1aaef8293abc69093b0a35c80d0f0e8`. The retained MIT license
is `web/DSH-LICENSE.txt`. Its original DeepSeek logo and audio recordings are not included.

The fullscreen sequence shows a Miu AI wordmark, then bilingual permission,
identity and verification-themed animation, followed by the bilingual welcome.
Those lines are visual narration only and do not request, read or verify permissions.
It plays automatically, with a local synthesized interface sound and Windows SAPI
English narration. Playback depends on the system audio device and installed voice.
The saved A-side boot color supplies the animation accent. On completion the
black backdrop fades away to reveal B's existing desktop and saved glow.

The existing authenticated A/B transport, login option and player protocol remain:
`STARTED` is printed once the document has loaded, `--color #RRGGBB` sets the
accent, `--check` probes WebView2, and only one player runs per session. Escape
is handled in both WPF and the WebView; a 65-second watchdog closes a stalled
player. The script loads only locally mapped resources; external requests and
permissions remain blocked by the native host.

Build on Windows with .NET SDK / Framework 4.8 and WebView2:

```powershell
dotnet build res/miu/boot-player/MiuBoot.csproj -c Release -o path/to/MiuBoot
```

Deploy the **whole** output `MiuBoot` directory beside the existing B executable,
not only its EXE. A and B integration, login trigger and saved settings require
real two-machine validation. This is a replacement player, not a new MSI.
