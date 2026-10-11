import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';

import 'miu_boot_player.dart';
import 'miu_toolbar_surface.dart';

class MiuBootControls extends StatefulWidget {
  const MiuBootControls({super.key, required this.ffi});
  final FFI ffi;

  @override
  State<MiuBootControls> createState() => _MiuBootControlsState();
}

class _MiuBootControlsState extends State<MiuBootControls> {
  bool _busy = false;
  String _status = '';
  static const _presets = [
    ('#48AAFF', '冰蓝'),
    ('#FF0000', '大红'),
    ('#A56CFF', '星紫'),
    ('#38E8CE', '青绿'),
    ('#FFD166', '鎏金'),
    ('#FFFFFF', '银白'),
  ];

  @override
  void initState() {
    super.initState();
    widget.ffi.chatModel.refreshMiuBootSettings();
  }

  Future<void> _save({String? color, bool? autoPlay}) async {
    final current = widget.ffi.chatModel.miuBootSettings;
    if (_busy || current == null) return;
    setState(() {
      _busy = true;
      _status = '正在保存到 B 机…';
    });
    final ok = await widget.ffi.chatModel.setMiuBootSettings(MiuBootSettings(
        color: color ?? current.color, autoPlay: autoPlay ?? current.autoPlay));
    if (mounted) {
      setState(() {
        _busy = false;
        _status = ok ? '已保存到 B 机，下次播放生效' : '保存失败，请检查连接后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation:
            Listenable.merge([widget.ffi.chatModel, widget.ffi.ffiModel]),
        builder: (context, _) {
          final chat = widget.ffi.chatModel;
          final settings = chat.miuBootSettings;
          final ready = !_busy &&
              !widget.ffi.closed &&
              widget.ffi.ffiModel.miuPeerAuthenticated &&
              settings != null;
          final color = settings?.color ?? '#48AAFF';
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: miuToolbarBlue),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('开机欢迎动画',
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(
                      tooltip: '读取 B 机设置',
                      iconSize: 18,
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _status = '正在读取 B 机设置…');
                              final ok = await chat.refreshMiuBootSettings();
                              if (mounted) {
                                setState(() => _status =
                                    ok
                                        ? '已读取 B 机设置'
                                        : '未收到新设置，请检查连接或升级 B 机');
                              }
                            },
                      icon: const Icon(Icons.refresh_rounded)),
                ]),
                const Text('颜色独立保存，不改变屏幕光效配色',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final preset in _presets)
                    ChoiceChip(
                        avatar: CircleAvatar(
                            radius: 7,
                            backgroundColor: Color(
                                int.parse(preset.$1.substring(1), radix: 16) |
                                    0xFF000000)),
                        label: Text(preset.$2),
                        selected: color == preset.$1,
                        selectedColor: miuToolbarBlue.withOpacity(.16),
                        backgroundColor: miuToolbarBlue.withOpacity(.04),
                        side:
                            BorderSide(color: miuToolbarBlue.withOpacity(.12)),
                        onSelected:
                            ready ? (_) => _save(color: preset.$1) : null),
                ]),
                TextButton.icon(
                    icon: const Icon(Icons.colorize_rounded, size: 17),
                    label: Text('自定义颜色  $color'),
                    onPressed: !ready
                        ? null
                        : () async {
                            final selected = await showColorPickerDialog(
                                context,
                                Color(int.parse(color.substring(1), radix: 16) |
                                    0xFF000000),
                                pickersEnabled: {
                                  ColorPickerType.accent: false,
                                  ColorPickerType.wheel: true
                                },
                                showColorCode: true);
                            if (mounted &&
                                selected.value !=
                                    (int.parse(color.substring(1), radix: 16) |
                                        0xFF000000)) {
                              await _save(
                                  color:
                                      '#${(selected.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}');
                            }
                          }),
                SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('登录 Windows 后自动播放'),
                    subtitle: const Text('B 机独立播放，A 离线也生效'),
                    activeColor: miuToolbarBlue,
                    value: settings?.autoPlay ?? false,
                    onChanged:
                        ready ? (value) => _save(autoPlay: value) : null),
                OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(_busy ? '请稍候…' : '立即在 B 播放'),
                    onPressed: !ready || chat.miuBootAvailable != true
                        ? null
                        : () async {
                            setState(() {
                              _busy = true;
                              _status = '等待 B 机播放器启动…';
                            });
                            final ok = await chat.playMiuBoot();
                            if (mounted) {
                              setState(() {
                                _busy = false;
                                _status = ok
                                    ? 'B 机已开始播放，可按 Esc 跳过'
                                    : '未能启动，请检查 B 机播放器及 WebView2';
                              });
                            }
                          }),
                Text(
                    settings == null
                        ? '等待 B 机读取设置；旧版 B 需升级后使用'
                        : chat.miuBootAvailable != true
                            ? 'B 机缺少播放器或 WebView2 Runtime'
                            : _status.isEmpty
                                ? '约 17 秒 · 播放后恢复 B 机原有光效'
                                : _status,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ]);
        },
      );
}
