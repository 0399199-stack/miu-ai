import 'package:flutter/material.dart';
import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/miu_glow_panel.dart';
import '../../desktop/widgets/miu_notice_composer.dart';

Future<void> showMiuMobileControls(BuildContext context, FFI ffi) async {
  await showModalBottomSheet<void>(context: context, isScrollControlled: true,
    useSafeArea: true, showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: .88,
      child: MiuMobileControls(ffi: ffi)));
}

class MiuMobileControls extends StatefulWidget {
  const MiuMobileControls({super.key, required this.ffi});
  final FFI ffi;
  @override
  State<MiuMobileControls> createState() => _MiuMobileControlsState();
}

class _MiuMobileControlsState extends State<MiuMobileControls> {
  bool _busy = false;

  Future<void> _change(Future<bool> Function() change) async {
    setState(() => _busy = true);
    final ok = await change();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(ok ? 'B 机已确认' : 'B 机未确认，请检查连接后重试');
  }

  Future<void> _text() async {
    final input = TextEditingController(text: widget.ffi.ffiModel.miuOverlayText);
    final value = await showDialog<String>(context: context,
      builder: (context) => AlertDialog(title: const Text('光效文字'),
        content: TextField(controller: input, maxLength: 160, minLines: 1, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('保存')),
        ]));
    input.dispose();
    if (!mounted || value == null || widget.ffi.closed) return;
    bind.sessionSetMiuOverlayText(sessionId: widget.ffi.sessionId, text: value);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.ffi.chatModel, widget.ffi.ffiModel]),
    builder: (context, _) {
      final ffi = widget.ffi;
      final chat = ffi.chatModel;
      final ready = !_busy && !ffi.closed && ffi.ffiModel.miuPeerAuthenticated;
      return SingleChildScrollView(padding: EdgeInsets.fromLTRB(20, 0, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const Expanded(child: Text('Miu 控制中心',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close))]),
          Text('已连接 · ${ffi.id}', style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 16),
          ExpansionTile(title: const Text('屏幕光效与开机动画'),
            leading: const Icon(Icons.auto_awesome), tilePadding: EdgeInsets.zero,
            children: [MiuGlowPanel(ffi: ffi, onClose: () => Navigator.pop(context),
              textControls: TextButton(onPressed: ready ? _text : null,
                child: const Text('更换文字')))]),
          ExpansionTile(title: const Text('桌面宠物'), leading: const Icon(Icons.pets),
            tilePadding: EdgeInsets.zero, children: [
              SwitchListTile(contentPadding: EdgeInsets.zero,
                title: const Text('显示 B 机宠物'),
                subtitle: Text(chat.miuPetVisible == null ? '等待 B 机状态' : '仅改变电脑上的宠物'),
                value: chat.miuPetVisible ?? false,
                onChanged: ready && chat.miuPetVisible != null
                  ? (v) => _change(() => chat.setMiuPetVisible(v)) : null),
              Wrap(spacing: 8, children: [for (final pet in [('luna', 'Miu Luna'), ('void', 'Miu Void')])
                ChoiceChip(label: Text(pet.$2), selected: chat.miuPetCharacter == pet.$1,
                  onSelected: ready && chat.miuPetProactiveEnabled != null
                    ? (_) => _change(() => chat.setMiuPetPreferences(character: pet.$1,
                        proactiveEnabled: chat.miuPetProactiveEnabled!)) : null)]),
              SwitchListTile(contentPadding: EdgeInsets.zero,
                title: const Text('随机关怀气泡'),
                value: chat.miuPetProactiveEnabled ?? false,
                onChanged: ready && chat.miuPetCharacter != null && chat.miuPetProactiveEnabled != null
                  ? (v) => _change(() => chat.setMiuPetPreferences(
                      character: chat.miuPetCharacter!, proactiveEnabled: v)) : null),
              SwitchListTile(contentPadding: EdgeInsets.zero,
                title: const Text('AI 自动回复'),
                subtitle: const Text('沿用 B 机保存的人设、模型及 Key'),
                value: chat.miuPetAiEnabled ?? false,
                onChanged: ready && chat.miuPetAiEnabled != null && chat.miuPetPersona != null &&
                    chat.miuPetReplyLength != null && chat.miuPetAiModel != null && chat.miuPetAiThinking != null
                  ? (v) => _change(() => chat.setMiuPetAiSettings(enabled: v,
                      persona: chat.miuPetPersona!, replyLength: chat.miuPetReplyLength!,
                      model: chat.miuPetAiModel!, thinking: chat.miuPetAiThinking!)) : null),
            ]),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('发送置顶通知'), subtitle: const Text('自定义标题、文字、颜色和显示时间'),
            trailing: const Icon(Icons.chevron_right), enabled: ready,
            onTap: () => showMiuNoticeComposer(context, ffi)),
        ]));
    });
}
