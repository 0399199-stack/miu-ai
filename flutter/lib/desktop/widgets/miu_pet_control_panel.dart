import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'miu_toolbar_surface.dart';

class MiuPetControlPanel extends StatefulWidget {
  const MiuPetControlPanel({super.key, required this.ffi, required this.onClose,
    required this.onChat, required this.onSettings});
  final FFI ffi;
  final VoidCallback onClose, onChat, onSettings;
  @override
  State<MiuPetControlPanel> createState() => _MiuPetControlPanelState();
}

class _MiuPetControlPanelState extends State<MiuPetControlPanel> {
  bool _pending = false;

  Future<void> _change(Future<bool> Function() action) async {
    setState(() => _pending = true);
    var ok = false;
    try { ok = await action(); } catch (_) { }
    if (!mounted) return;
    setState(() => _pending = false);
    if (!ok) showToast('B 机未确认设置，请重试');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.ffi.chatModel, widget.ffi.ffiModel]),
    builder: (context, _) {
      final chat = widget.ffi.chatModel;
      final visible = chat.miuPetVisible;
      final ready = !_pending && !widget.ffi.closed &&
          widget.ffi.ffiModel.miuPeerAuthenticated && widget.ffi.ffiModel.isPeerWindows;
      final aiReady = ready && chat.miuPetAiEnabled != null &&
          chat.miuPetPersona != null && chat.miuPetReplyLength != null &&
          chat.miuPetAiModel != null && chat.miuPetAiThinking != null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MiuPanelHeading('B 机宠物', onClose: widget.onClose),
        Row(children: [
          Icon(Icons.circle, size: 8, color: visible == null ? Colors.amber
              : visible ? const Color(0xFF24BD87) : Colors.grey),
          const SizedBox(width: 8),
          Text(_pending ? '等待 B 机确认…' : visible == null ? '正在读取 B 机状态…'
              : visible ? '当前已显示' : '当前已隐藏', style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('显示宠物'), value: visible == true,
          onChanged: ready && visible != null
              ? (value) => _change(() => chat.setMiuPetVisible(value)) : null),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('AI 自动回复'), value: chat.miuPetAiEnabled == true,
          onChanged: aiReady ? (value) => _change(() => chat.setMiuPetAiSettings(
            enabled: value, persona: chat.miuPetPersona!, replyLength: chat.miuPetReplyLength!,
            model: chat.miuPetAiModel!, thinking: chat.miuPetAiThinking!)) : null),
        const Divider(),
        MiuPanelAction(icon: Icons.chat_bubble_outline_rounded, label: '打开聊天',
          onPressed: () { widget.onClose(); widget.onChat(); }),
        MiuPanelAction(icon: Icons.tune_rounded, label: '宠物设置',
          onPressed: aiReady ? () { widget.onClose(); widget.onSettings(); } : null),
      ]);
    },
  );
}
