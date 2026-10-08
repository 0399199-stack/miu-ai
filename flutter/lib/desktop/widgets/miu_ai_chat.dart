import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'miu_ai_credentials.dart';
import 'miu_ai_history.dart';
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
        _modelReader = (() => bind.mainGetLocalOption(key: 'miu-ai-model')),
        _thinkingReader =
            (() => bind.mainGetLocalOption(key: 'miu-ai-thinking')),
        _client = MiuDeepSeekClient(),
        _persistHistory = true {
    _messages.addAll(MiuAiHistoryStore.instance.recent
        .map((entry) => MiuLocalMessage(entry.text, fromUser: entry.fromUser)));
  }

  @visibleForTesting
  MiuAiConversation.forTesting({
    required String? Function() keyReader,
    required bool Function() enabledReader,
    required String Function() personaReader,
    required int Function() lengthReader,
    String Function()? modelReader,
    String Function()? thinkingReader,
    required MiuDeepSeekClient client,
  })  : _keyReader = keyReader,
        _enabledReader = enabledReader,
        _personaReader = personaReader,
        _lengthReader = lengthReader,
        _modelReader = modelReader ?? (() => 'deepseek-flash'),
        _thinkingReader = thinkingReader ?? (() => 'none'),
        _client = client,
        _persistHistory = false;

  static final instance = MiuAiConversation._();
  final _messages = <MiuLocalMessage>[];
  final _credentials = MiuAiCredentialStore();
  final String? Function() _keyReader;
  final bool Function() _enabledReader;
  final String Function() _personaReader;
  final int Function() _lengthReader;
  final String Function() _modelReader;
  final String Function() _thinkingReader;
  final MiuDeepSeekClient _client;
  final bool _persistHistory;
  bool _busy = false;

  List<MiuLocalMessage> get messages => List.unmodifiable(_messages);
  bool get busy => _busy;
  bool get enabled => _enabledReader();
  bool get hasKey => _keyReader()?.isNotEmpty == true;
  String get persona => _personaReader();
  String get model => normalizeMiuDeepSeekModel(_modelReader());
  String get thinking => normalizeMiuDeepSeekThinking(_thinkingReader());
  int get replyLength => _lengthReader().clamp(1, 3);

  Future<void> setModel(String value) async {
    await bind.mainSetLocalOption(
        key: 'miu-ai-model', value: normalizeMiuDeepSeekModel(value));
    notifyListeners();
  }

  Future<void> setThinking(String value) async {
    await bind.mainSetLocalOption(
        key: 'miu-ai-thinking', value: normalizeMiuDeepSeekThinking(value));
    notifyListeners();
  }

  Future<void> setReplyLength(int value) async {
    await bind.mainSetLocalOption(
        key: 'miu-ai-reply-length', value: value.clamp(1, 3).toString());
    notifyListeners();
  }

  Future<void> setPersona(String value) async {
    if (value.length > 1500) throw const FormatException('人设不能超过 1500 字');
    await bind.mainSetLocalOption(key: 'miu-ai-persona', value: value.trim());
    notifyListeners();
  }

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
      if (_persistHistory) {
        await MiuAiHistoryStore.instance.add(prompt, fromUser: true);
      }
      answer.text = await _client.streamReply(
        apiKey: key,
        persona: _personaReader(),
        replyLength: _lengthReader(),
        model: model,
        thinking: thinking,
        turns: turns,
        onPartial: (partial) {
          answer.text = partial;
          notifyListeners();
        },
      );
      if (_persistHistory && answer.text.isNotEmpty) {
        await MiuAiHistoryStore.instance.add(answer.text, fromUser: false);
      }
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
    final personaInput = TextEditingController(text: _conversation.persona);
    String? error;
    var enabled = _conversation.enabled;
    var model = _conversation.model;
    var thinking = _conversation.thinking;
    var replyLength = _conversation.replyLength;
    var removeKey = false;
    var enabledBeforeRemove = enabled;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
        return AlertDialog(
          backgroundColor: const Color(0xFFF5F7FC),
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(children: [
            const Expanded(child: Text('Miu · DeepSeek 设置')),
            IconButton(
              tooltip: '取消，不保存',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 310,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(removeKey
                    ? '保存后将从这台电脑移除 API Key'
                    : _conversation.hasKey
                        ? 'API Key 已保存在这台电脑的 Windows 凭据管理器'
                        : '请在 B 机本地输入 API Key'),
                const SizedBox(height: 12),
                TextField(
                  controller: keyInput,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (_) {
                    if (removeKey) {
                      update(() {
                        removeKey = false;
                        enabled = enabledBeforeRemove;
                      });
                    }
                  },
                  decoration: const InputDecoration(
                      labelText: '输入新的 DeepSeek API Key',
                      border: OutlineInputBorder()),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('开启 AI 聊天'),
                  value: enabled,
                  onChanged: removeKey
                      ? null
                      : (value) => update(() {
                            enabled = value;
                            error = null;
                          }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: model,
                  decoration: const InputDecoration(
                      labelText: 'DeepSeek 模型', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'deepseek-flash', child: Text('DeepSeek Flash')),
                    DropdownMenuItem(
                        value: 'deepseek-v4-pro',
                        child: Text('DeepSeek V4 Pro')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    update(() => model = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: thinking,
                  decoration: const InputDecoration(
                      labelText: '深度思考', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('关闭')),
                    DropdownMenuItem(value: 'low', child: Text('轻度')),
                    DropdownMenuItem(value: 'high', child: Text('深度')),
                    DropdownMenuItem(value: 'max', child: Text('最大')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    update(() => thinking = value);
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                    alignment: Alignment.centerLeft, child: Text('回复长度')),
                Wrap(spacing: 8, children: [
                  for (final option in const [
                    (1, '一句话'),
                    (2, '两句话'),
                    (3, '详细')
                  ])
                    ChoiceChip(
                      label: Text(option.$2),
                      selected: replyLength == option.$1,
                      onSelected: (_) => update(() => replyLength = option.$1),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: personaInput,
                  maxLength: 1500,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '人设提示词',
                    helperText: '留空使用默认猫咪人设',
                    border: OutlineInputBorder(),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            if (_conversation.hasKey)
              TextButton(
                  onPressed: () {
                    update(() {
                      removeKey = !removeKey;
                      if (removeKey) {
                        enabledBeforeRemove = enabled;
                        enabled = false;
                        keyInput.clear();
                      } else {
                        enabled = enabledBeforeRemove;
                      }
                      error = null;
                    });
                  },
                  child: Text(removeKey ? '保留 Key' : '移除 Key')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            FilledButton(
                onPressed: () async {
                  if (saving) return;
                  update(() => saving = true);
                  try {
                    if (enabled &&
                        (removeKey ||
                            (!_conversation.hasKey &&
                                keyInput.text.trim().isEmpty))) {
                      throw StateError('请先设置 DeepSeek API Key');
                    }
                    if (personaInput.text.length > 1500) {
                      throw const FormatException('人设不能超过 1500 字');
                    }
                    if (removeKey) {
                      await _conversation.removeKey();
                    } else if (keyInput.text.trim().isNotEmpty) {
                      await _conversation.setKey(keyInput.text);
                    }
                    if (!removeKey) await _conversation.setEnabled(enabled);
                    await _conversation.setModel(model);
                    await _conversation.setThinking(thinking);
                    await _conversation.setReplyLength(replyLength);
                    await _conversation.setPersona(personaInput.text);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    if (dialogContext.mounted) {
                      update(() {
                        saving = false;
                        error = e
                            .toString()
                            .replaceFirst('FormatException: ', '')
                            .replaceFirst('Bad state: ', '');
                      });
                    }
                  }
                },
                child: const Text('保存设置')),
          ],
        );
      }),
    );
    keyInput.clear();
    keyInput.dispose();
    personaInput.dispose();
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
              : LayoutBuilder(
                  builder: (context, constraints) => ListView.builder(
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
                              constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * .9),
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
                      )),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                maxLength: 1000,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
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
