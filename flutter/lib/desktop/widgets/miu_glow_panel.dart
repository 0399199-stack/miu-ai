import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'miu_toolbar_surface.dart';

class MiuGlowPanel extends StatefulWidget {
  const MiuGlowPanel({super.key, required this.ffi, required this.onClose,
    required this.textControls});
  final FFI ffi;
  final VoidCallback onClose;
  final Widget textControls;

  @override
  State<MiuGlowPanel> createState() => _MiuGlowPanelState();
}

class _MiuGlowPanelState extends State<MiuGlowPanel> {
  FfiModel get model => widget.ffi.ffiModel;
  double? _intensityDraft;
  double? _periodDraft;

  Future<void> _setMode(String mode) async {
    final supported = model.miuOverlayModeSupported;
    model.markMiuOverlayPending();
    try {
      if (supported) {
        await (bind as dynamic).sessionSetMiuOverlayMode(
          sessionId: widget.ffi.sessionId, mode: mode);
      } else {
        await bind.sessionSetMiuOverlayEnabled(
          sessionId: widget.ffi.sessionId, enabled: mode != 'off');
      }
    } catch (_) {
      showToast('光效设置未发送，请重试');
      bind.sessionQueryMiuOverlaySettings(sessionId: widget.ffi.sessionId);
    }
  }

  void _settings({String? color, String? effect, int? intensity, int? period}) {
    final enabled = model.miuOverlayEnabled == true;
    model.markMiuOverlayPending();
    bind.sessionSetMiuOverlaySettings(sessionId: widget.ffi.sessionId,
      enabled: enabled, color: color ?? model.miuOverlayColor,
      intensity: intensity ?? model.miuOverlayIntensity,
      periodMs: period ?? model.miuOverlayPeriodMs,
      effect: effect ?? model.miuOverlayEffect);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final ready = model.miuPeerAuthenticated && !widget.ffi.closed &&
          model.isPeerWindows && model.miuOverlayEnabled != null;
      final enabled = model.miuOverlayEnabled == true;
      final intensity = _intensityDraft ?? model.miuOverlayIntensity.toDouble();
      final period = _periodDraft ?? model.miuOverlayPeriodMs.toDouble();
      const colors = [0xFF317CFF, 0xFFFF4D5B, 0xFFFFCF2E,
        0xFF9456FF, 0xFF24D866, 0xFFFFFFFF];
      const labels = ['蓝色', '红色', '黄色', '紫色', '绿色', '白色'];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MiuPanelHeading('屏幕光效', onClose: widget.onClose),
        for (final option in const [('off', '关闭'), ('session', '连接时开启'), ('always', '始终开启')])
          RadioListTile<String>(
            activeColor: miuToolbarBlue,
            dense: true, contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            title: Text(option.$2), value: option.$1, groupValue: model.miuOverlayMode,
            subtitle: option.$1 == 'always' && !model.miuOverlayModeSupported
                ? const Text('需升级 B 机后使用', style: TextStyle(fontSize: 11)) : null,
            onChanged: ready && (option.$1 != 'always' || model.miuOverlayModeSupported)
                ? (value) => _setMode(value!) : null,
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: miuToolbarBlue.withOpacity(.06),
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.circle, size: 8, color: model.miuOverlayEnabled == null
                ? Colors.amber : enabled ? const Color(0xFF24BD87) : Colors.grey),
            const SizedBox(width: 7),
            Expanded(child: Text(model.miuOverlayEnabled == null ? '等待 B 机确认…'
                : !enabled ? '当前已关闭'
                : model.miuOverlayMode == 'always' ? '当前已开启 · 断开后继续显示'
                : '当前已开启 · 随连接显示', style: const TextStyle(fontSize: 12))),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < colors.length; i++)
            Tooltip(message: labels[i], child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: ready ? () => _settings(color: '#${colors[i].toRadixString(16).substring(2).toUpperCase()}') : null,
              child: Container(width: 29, height: 29, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(width: 2, color: model.miuOverlayColor.toUpperCase() == '#${colors[i].toRadixString(16).substring(2).toUpperCase()}'
                      ? miuToolbarBlue : Colors.transparent)),
                child: DecoratedBox(decoration: BoxDecoration(color: Color(colors[i]),
                  shape: BoxShape.circle, border: Border.all(color: Colors.black12))),
              ),
            )),
          SizedBox(width: 29, height: 29, child: IconButton(
            padding: EdgeInsets.zero, tooltip: '自定义颜色', iconSize: 19,
            onPressed: !ready ? null : () async {
              final initial = Color(int.parse(model.miuOverlayColor.substring(1), radix: 16) | 0xFF000000);
              final selected = await showColorPickerDialog(context, initial,
                pickersEnabled: {ColorPickerType.accent: false, ColorPickerType.wheel: true},
                showColorCode: true);
              if (mounted && selected != initial) {
                _settings(color: '#${(selected.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}');
              }
            }, icon: const Icon(Icons.add_rounded))),
        ]),
        const SizedBox(height: 18),
        Text('强度  ${intensity.round()}%'),
        Slider(value: intensity, min: 0, max: 100, divisions: 100,
          activeColor: miuToolbarBlue,
          onChanged: ready ? (value) => setState(() => _intensityDraft = value) : null,
          onChangeEnd: ready ? (value) {
            _settings(intensity: value.round());
            setState(() => _intensityDraft = null);
          } : null),
        const Text('动画'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final effect in const [('breathing', '呼吸'), ('marquee', '流光'),
            ('steady', '静态'), ('blink', '闪烁'), ('heartbeat', '心跳')])
            ChoiceChip(label: Text(effect.$2), selected: model.miuOverlayEffect == effect.$1,
              selectedColor: miuToolbarBlue.withOpacity(.16),
              backgroundColor: miuToolbarBlue.withOpacity(.04),
              side: BorderSide(color: miuToolbarBlue.withOpacity(.12)),
              onSelected: ready ? (_) => _settings(effect: effect.$1) : null),
        ]),
        const SizedBox(height: 14),
        Text('节奏  ${(period / 1000).toStringAsFixed(1)} 秒 / 次'),
        Slider(value: period, min: 1200, max: 10000, divisions: 88,
          activeColor: miuToolbarBlue,
          onChanged: ready ? (value) => setState(() => _periodDraft = value) : null,
          onChangeEnd: ready ? (value) {
            _settings(period: value.round());
            setState(() => _periodDraft = null);
          } : null),
        const Divider(),
        Row(children: [const Expanded(child: Text('文字显示')), widget.textControls]),
      ]);
    },
  );
}
