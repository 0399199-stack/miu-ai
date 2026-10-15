import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/model.dart';

import 'miu_glass.dart';
import 'miu_notice.dart';

Future<void> showMiuNoticeComposer(BuildContext context, FFI ffi) async {
  final dialogContext = Navigator.of(context, rootNavigator: true).context;
  await showDialog<void>(
    context: dialogContext,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => MiuNoticeComposer(onSend: ffi.chatModel.sendMiuNotice),
  );
}

class MiuNoticeComposer extends StatefulWidget {
  const MiuNoticeComposer({super.key, required this.onSend});

  final Future<bool> Function(MiuNotice notice) onSend;

  @override
  State<MiuNoticeComposer> createState() => _MiuNoticeComposerState();
}

class _MiuNoticeComposerState extends State<MiuNoticeComposer> {
  final _title = TextEditingController(text: 'Miu AI');
  final _text = TextEditingController();
  final _seconds = TextEditingController(text: '15');
  bool _sound = true;
  bool _sending = false;
  bool _sent = false;
  String? _status;

  MiuNotice? get _notice {
    final seconds = int.tryParse(_seconds.text);
    if (seconds == null) return null;
    return MiuNotice.parse({
      'title': _title.text,
      'text': _text.text,
      'seconds': seconds,
      'sound': _sound,
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _changed(String _) => setState(() => _status = null);

  Future<void> _send() async {
    final notice = _notice;
    if (_sending || notice == null) return;
    setState(() {
      _sending = true;
      _sent = false;
      _status = '正在等待 B 机确认…';
    });
    var sent = false;
    try {
      sent = await widget.onSend(notice);
    } catch (_) {
      sent = false;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = sent;
      _status = sent ? 'B 机已显示通知' : '发送失败，请检查连接及 B 机版本后重试';
    });
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: MiuGlass(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.campaign_rounded,
                        color: Color(0xFF3979D1)),
                    const SizedBox(width: 10),
                    const Expanded(
                        child: Text('发送置顶通知',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text('B 机置顶显示，可手动关闭；新通知替换旧通知并重新计时',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('miu-notice-title'),
                    controller: _title,
                    enabled: !_sending,
                    maxLength: 60,
                    maxLines: 1,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '输入通知标题',
                        border: OutlineInputBorder()),
                    onChanged: _changed,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('miu-notice-text'),
                    controller: _text,
                    enabled: !_sending,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 1200,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                        labelText: '通知内容',
                        hintText: '输入要在 B 机显示的文字',
                        border: OutlineInputBorder()),
                    onChanged: _changed,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('miu-notice-seconds'),
                    controller: _seconds,
                    enabled: !_sending,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                        labelText: '自动关闭时间',
                        suffixText: '秒',
                        helperText: '1–300 秒，也可在 B 机手动关闭',
                        border: OutlineInputBorder()),
                    onChanged: _changed,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('播放一次提示音'),
                    value: _sound,
                    onChanged: _sending
                        ? null
                        : (value) => setState(() {
                              _sound = value;
                              _status = null;
                            }),
                  ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_status!,
                            style: TextStyle(
                                color: _sending
                                    ? Colors.blueGrey
                                    : _sent
                                        ? const Color(0xFF278259)
                                        : Theme.of(context).colorScheme.error)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      key: const ValueKey('miu-notice-send'),
                      onPressed: !_sending && _notice != null ? _send : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(_sending ? '等待确认…' : '发送到 B 机'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
