import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'miu_ai_credentials.dart';
import 'miu_deepseek_client.dart';

class MiuLocalMessage {
  MiuLocalMessage(this.text, {this.fromUser = false, this.inContext = true});

  String text;
  final bool fromUser;
  final bool inContext;
}

class MiuAiConversation extends ChangeNotifier {
  MiuAiConversation._()
      : _keyReader = (() => MiuAiCredentialStore().read()),
        _enabledReader =
            (() => bind.mainGetLocalOption(key: 'miu-ai-enabled') == 'Y'),
        _personaReader = (() => bind.mainGetLocalOption(key: 'miu-ai-persona')),
        _lengthReader = (() =>
            int.tryParse(bind.mainGetLocalOption(key: 'miu-ai-reply-length')) ??
            1),
        _client = MiuDeepSeekClient();

  @visibleForTesting
  MiuAiConversation.forTesting({
    required String? Function() keyReader,
    required bool Function() enabledReader,
    required String Function() personaReader,
    required int Function() lengthReader,
    required MiuDeepSeekClient client,
  })  : _keyReader = keyReader,
        _enabledReader = enabledReader,
        _personaReader = personaReader,
        _lengthReader = lengthReader,
        _client = client;

  static final instance = MiuAiConversation._();
  final _messages = <MiuLocalMessage>[];
  final _credentials = MiuAiCredentialStore();
  final String? Function() _keyReader;
  final bool Function() _enabledReader;
  final String Function() _personaReader;
  final int Function() _lengthReader;
  final MiuDeepSeekClient _client;
  bool _busy = false;

  List<MiuLocalMessage> get messages => List.unmodifiable(_messages);
  bool get busy => _busy;
  bool get enabled => _enabledReader();
  bool get hasKey => _keyReader()?.isNotEmpty == true;

  Future<void> setKey(String key) async {
    _credentials.write(key);
    await bind.mainSetLocalOption(key: 'miu-ai-enabled', value: 'Y');
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value && !hasKey) throw StateError('请先设置 DeepSeek API Key');
    await bind.mainSetLocalOption(
        key: 'miu-ai-enabled', value: value ? 'Y' : 'N');
    notifyListeners();
  }

  Future<void> removeKey() async {
    await setEnabled(false);
    _credentials.delete();
    notifyListeners();
  }

  Future<void> send(String text) async {
    final prompt = text.trim();
    if (_busy || prompt.isEmpty) return;
    final key = _keyReader();
    if (!enabled || key == null || key.isEmpty) {
      _messages.insert(
          0,
          MiuLocalMessage(
              key == null || key.isEmpty
                  ? '先在这台电脑设置 DeepSeek API Key 吧。'
                  : 'Miu 的 AI 聊天已关闭。',
              inContext: false));
      notifyListeners();
      return;
    }
    final turns = <MiuAiTurn>[
      for (final message in _messages.reversed)
        if (message.inContext && message.text.isNotEmpty)
          MiuAiTurn(message.fromUser ? 'user' : 'assistant', message.text),
      MiuAiTurn('user', prompt),
    ];
    _messages.insert(0, MiuLocalMessage(prompt, fromUser: true));
    final answer = MiuLocalMessage('');
    _messages.insert(0, answer);
    _busy = true;
    notifyListeners();
    try {
      answer.text = await _client.streamReply(
        apiKey: key,
        persona: _personaReader(),
        replyLength: _lengthReader(),
        turns: turns,
        onPartial: (partial) {
          answer.text = partial;
          notifyListeners();
        },
      );
    } catch (error) {
      _messages.remove(answer);
      _messages.insert(
          0,
          MiuLocalMessage(
              error is MiuAiRequestError ? error.message : '网络暂时不可用。',
              inContext: false));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

class MiuAiChatView extends StatefulWidget {
  const MiuAiChatView({super.key});

  @override
  State<MiuAiChatView> createState() => _MiuAiChatViewState();
}

class _MiuAiChatViewState extends State<MiuAiChatView> {
  final _input = TextEditingController();
  final _conversation = MiuAiConversation.instance;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _conversation.busy) return;
    _input.clear();
    await _conversation.send(text);
  }

  Future<void> _showKeySettings() async {
    final keyInput = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
        return AlertDialog(
          title: const Text('Miu · DeepSeek 设置'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 250,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_conversation.hasKey
                    ? 'API Key 已保存在这台电脑的 Windows 凭据管理器'
                    : '请在 B 机本地输入 API Key'),
                const SizedBox(height: 12),
                TextField(
                  controller: keyInput,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: '输入新的 DeepSeek API Key',
                      border: OutlineInputBorder()),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('开启 AI 聊天'),
                  value: _conversation.enabled,
                  onChanged: (value) async {
                    try {
                      await _conversation.setEnabled(value);
                      update(() => error = null);
                    } catch (e) {
                      update(() =>
                          error = e.toString().replaceFirst('Bad state: ', ''));
                    }
                  },
                ),
              ]),
            ),
          ),
          actions: [
            if (_conversation.hasKey)
              TextButton(
                  onPressed: () async {
                    await _conversation.removeKey();
                    update(() => error = null);
                  },
                  child: const Text('移除 Key')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭')),
            FilledButton(
                onPressed: () async {
                  try {
                    await _conversation.setKey(keyInput.text);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    update(() => error =
                        e.toString().replaceFirst('FormatException: ', ''));
                  }
                },
                child: const Text('保存 Key')),
          ],
        );
      }),
    );
    keyInput.clear();
    keyInput.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _conversation,
      builder: (context, _) => Column(children: [
        Row(children: [
          const SizedBox(width: 14),
          const Expanded(child: Text('和 Miu 聊聊天')),
          IconButton(
              tooltip: 'DeepSeek 设置',
              onPressed: _showKeySettings,
              icon: const Icon(Icons.settings_outlined)),
        ]),
        Expanded(
          child: _conversation.messages.isEmpty
              ? const Center(child: Text('嗨，我是 Miu。今天想聊什么？'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: _conversation.messages.length,
                  itemBuilder: (context, index) {
                    final message = _conversation.messages[index];
                    return Align(
                      alignment: message.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 265),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 9),
                        decoration: BoxDecoration(
                          color: message.fromUser
                              ? const Color(0xFF657BE9)
                              : Colors.white.withOpacity(.86),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: SelectableText(
                            message.text.isEmpty ? '…' : message.text,
                            style: TextStyle(
                                color: message.fromUser
                                    ? Colors.white
                                    : const Color(0xFF263252))),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLength: 1000,
                maxLines: 1,
                onSubmitted: (_) => unawaited(_send()),
                decoration: InputDecoration(
                  hintText: '发消息给 Miu',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white.withOpacity(.75),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              tooltip: '发送',
              onPressed: _conversation.busy ? null : () => unawaited(_send()),
              icon: _conversation.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
