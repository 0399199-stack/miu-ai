# Miu AI Windows welcome player

## Integration

- A: remote toolbar → 光效 → 开机欢迎动画. Six presets (冰蓝、大红、星紫、青绿、鎏金、银白), a color wheel/hex picker, login playback toggle, and “立即在 B 播放”. Red is `#FF0000`.
- B owns `miu-boot-settings` in its existing local preferences. Defaults: ice blue and login playback on. Saving a boot color does not modify real edge glow settings.
- The existing authenticated desktop chat-control transport carries `boot-state`, `boot-settings`, and `boot-play`. Reconnection resets A's cache and queries B. Old B versions keep controls disabled. A reports playback success only after the native player acknowledges `STARTED`.
- B's existing MSI Startup shortcut adds `--miu-login`. Only that CM launch checks auto-play; ordinary remote connections do not start the animation. No separate Windows Run registration or taskbar setting changes.
- Player: .NET Framework 4.8, WPF and WebView2 CompositionControl. Uses the installed WebView2 Runtime; it does not install a runtime silently. Fixed local assets only, external navigation/downloads/permissions blocked, no commands or screen/data collection.
- The first 12 seconds reuse the approved revision-8 realtime HTML animation. Native WPF renders READY on an opaque black backdrop, with all text using the exact selected color. The local Miu Circuit Bold font places Miu AI above a larger READY. After the text fades out, a soft radial opacity fade reveals the desktop from center to edges, including the existing saved B glow. The 18-second sequence ends with a transparent tail before closing; it never overwrites the real overlay state. Native composition avoids reliance on transparent browser backgrounds on [WebView2 Runtime 154](https://github.com/MicrosoftEdge/WebView2Feedback/issues/5752).
- Native fullscreen on the primary monitor. Esc skips; the player closes after the sequence, renderer failure or a 35-second watchdog. One concurrent player per Windows session.

## Build

From the repository root:

```powershell
dotnet build res/miu/boot-player/MiuBoot.csproj -c Release -o rustdesk/MiuBoot
```

Ship the complete `MiuBoot` directory beside `MiuAI.exe`, including WebView2 loader DLLs and `web/`. `MiuBoot.exe --check` probes the runtime and entry asset. `MiuBoot.exe --color '#FF0000'` plays red. The Miu Windows test-build workflow builds/copies this directory; MSI's existing recursive file collection includes it.

Do not replace the whole source tree or reuse an old A UI binary: the Flutter UI changes also need a new Windows build. The standalone prototype directory was not changed by this integration.

## Verification — 2026-10-12

Completed locally:

- Native Release build, zero compiler warnings/errors.
- Native full-screen red terminal playback (2560×1440); no title bar or helper controls.
- Complete play with transparent READY over the actual desktop and normal exit (~18 seconds including initialization).
- Esc input to the native window, `skipped` result, process/window exited.
- Flutter preferences tests: presets/custom hex, restart readback, invalid values, disabled login, explicit playback, save/start failure.
- Flutter UI tests at 300-pixel panel width: six presets, red selection, independent login toggle, play acknowledgment, unsupported older B.
- Existing chat image path, CM lifecycle, and glass toolbar tests.

Not yet verified:

- New full A portable/B MSI builds and installation. This machine has no detected Visual Studio C++ build component; CI has not been dispatched for this change.
- Actual two-machine A→B updates/reconnect and B logout/login with A offline.
- Handoff to the actual B edge-glow process in enabled/off/session/always modes.
- Physical multi-monitor behavior, varied DPI/GPU/Windows/WebView2 versions, or measured display frame rate. No 60fps claim.

## Regression surface

Existing files changed only where needed:

- `flutter/lib/desktop/widgets/miu_glow_panel.dart`: embeds the new boot controls.
- `flutter/lib/models/chat_model.dart`: typed boot settings, three authenticated control actions, response/reset plumbing.
- `flutter/lib/models/model.dart`: query B on authentication/reconnection.
- `flutter/lib/main.dart`: login-marked CM startup calls the independent player.
- `res/msi/Package/Components/RustDesk.wxs`: login marker on the existing B shortcut.
- `.github/workflows/miu-ai-test-windows-x64.yml`: targeted tests, native build and packaging checks.

Other functionality keeps its existing path. No Rust protocol/bridge changes, no real-glow implementation changes, no pet/chat behavior changes.

## Asset licenses

Miu Circuit Bold is a renamed static weight-700 instance of Orbitron, distributed under SIL OFL 1.1. The source notice and original OFL license are in `web/assets/fonts/`. It is bundled locally, without installing a Windows font.

The approved Varesco demo font and its derived logo outlines are **personal-use-only**. This local integration is not a commercial redistribution license. Obtain the required Varesco license before distributing the font/outlines commercially, or replace them with licensed artwork. Notices are in `web/assets/fonts/`. Space Grotesk and JetBrains Mono retain their OFL notices. WebView2 SDK is restored from the pinned Microsoft NuGet package.
