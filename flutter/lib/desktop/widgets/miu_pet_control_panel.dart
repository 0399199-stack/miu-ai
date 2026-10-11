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
      final preferencesReady = ready && chat.miuPetCharacter != null &&
          chat.miuPetProactiveEnabled != null;
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
        Row(children: [
          for (final pet in const [
            ('luna', 'Miu Luna', '温柔 · 聪明 · 陪伴', 'assets/miu_luna_preview.png'),
            ('void', 'Miu Void', '冷酷 · 毒舌 · 战斗', 'assets/miu_void_head.png'),
          ])
            Expanded(child: Padding(
              padding: EdgeInsets.only(right: pet.$1 == 'luna' ? 6 : 0,
                  left: pet.$1 == 'void' ? 6 : 0),
              child: OutlinedButton(
                onPressed: preferencesReady ? () => _change(() =>
                    chat.setMiuPetPreferences(character: pet.$1,
                        proactiveEnabled: chat.miuPetProactiveEnabled!)) : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  backgroundColor: chat.miuPetCharacter == pet.$1
                      ? miuToolbarBlue.withOpacity(.10) : Colors.transparent,
                  side: BorderSide(color: chat.miuPetCharacter == pet.$1
                      ? miuToolbarBlue : miuToolbarBlue.withOpacity(.12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Column(children: [
                  Image.asset(pet.$4, width: 62, height: 62, cacheWidth: 180),
                  const SizedBox(height: 6),
                  Text(pet.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(pet.$3, style: const TextStyle(fontSize: 10)),
                ]),
              ),
            )),
        ]),
        if (chat.miuPetCharacter == null)
          const Padding(padding: EdgeInsets.only(top: 7),
            child: Text('角色切换需新版 B 机支持', style: TextStyle(fontSize: 11))),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('显示宠物'), value: visible == true,
          onChanged: ready && visible != null
              ? (value) => _change(() => chat.setMiuPetVisible(value)) : null),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('AI 自动回复'), value: chat.miuPetAiEnabled == true,
          onChanged: aiReady ? (value) => _change(() => chat.setMiuPetAiSettings(
            enabled: value, persona: chat.miuPetPersona!, replyLength: chat.miuPetReplyLength!,
            model: chat.miuPetAiModel!, thinking: chat.miuPetAiThinking!)) : null),
        SwitchListTile.adaptive(contentPadding: EdgeInsets.zero,
          title: const Text('随机互动'),
          subtitle: Text(chat.miuPetProactiveEnabled == true && chat.miuPetAiEnabled != true
              ? 'AI 已关闭，随机互动暂停'
              : 'DeepSeek 生成 · 每 30–90 分钟', style: const TextStyle(fontSize: 11)),
          value: chat.miuPetProactiveEnabled == true,
          onChanged: preferencesReady ? (value) => _change(() =>
              chat.setMiuPetPreferences(character: chat.miuPetCharacter!,
                  proactiveEnabled: value)) : null),
        const Divider(),
        MiuPanelAction(icon: Icons.chat_bubble_outline_rounded, label: '打开聊天',
          onPressed: () { widget.onClose(); widget.onChat(); }),
        MiuPanelAction(icon: Icons.tune_rounded, label: '宠物设置',
          onPressed: aiReady ? () { widget.onClose(); widget.onSettings(); } : null),
      ]);
    },
  );
}
