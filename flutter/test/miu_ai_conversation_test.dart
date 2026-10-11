import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_ai_chat.dart';
import 'package:flutter_hbb/desktop/widgets/miu_deepseek_client.dart';
import 'package:flutter_hbb/desktop/widgets/miu_pet_preferences.dart';

class _FakeDeepSeek extends MiuDeepSeekClient {
  int calls = 0;
  List<MiuAiTurn> sentTurns = [];
  String sentModel = '';
  String sentThinking = '';
  String sentPersona = '';
  int sentLength = 0;
  String reply = '你好';
  Completer<String>? pending;
  bool fail = false;

  @override
  Future<String> streamReply({
    required String apiKey,
    required String persona,
    required int replyLength,
    String model = 'deepseek-flash',
    String thinking = 'none',
    required List<MiuAiTurn> turns,
    required void Function(String) onPartial,
  }) async {
    calls++;
    sentTurns = turns;
    sentModel = model;
    sentThinking = thinking;
    sentPersona = persona;
    sentLength = replyLength;
    if (fail) throw const MiuAiRequestError('网络暂时不可用');
    onPartial(reply);
    if (pending != null) return pending!.future;
    return reply;
  }
}

void main() {
  test('B can chat without A and AI-off starts no request', () async {
    final client = _FakeDeepSeek();
    var enabled = true;
    final chat = MiuAiConversation.forTesting(
      keyReader: () => 'test-only',
      enabledReader: () => enabled,
      personaReader: () => '',
      lengthReader: () => 1,
      modelReader: () => 'deepseek-v4-pro',
      thinkingReader: () => 'high',
      client: client,
    );
    addTearDown(chat.dispose);

    await chat.send('嗨');
    expect(client.calls, 1);
    expect(chat.messages.where((m) => m.text == '你好'), hasLength(1));
    expect(client.sentTurns.last.role, 'user');
    expect(client.sentTurns.last.content, '嗨');
    expect(client.sentModel, 'deepseek-v4-pro');
    expect(client.sentThinking, 'high');

    final observedSettings = <bool>[];
    chat.addListener(() => observedSettings.add(chat.enabled));
    enabled = false;
    chat.refreshSettings();
    expect(observedSettings, [false]);
    enabled = true;
    chat.refreshSettings();
    expect(observedSettings, [false, true]);
    enabled = false;
    await chat.send('不要发送');
    expect(client.calls, 1);
    expect(chat.messages.first.text, contains('已关闭'));
  });

  test(
      'roles preserve persona and proactive replies add only one assistant turn',
      () async {
    final options = <String, String>{};
    final preferences = MiuPetPreferences.forTesting(
        read: (key) => options[key] ?? '',
        write: (key, value) async => options[key] = value);
    final client = _FakeDeepSeek();
    final chat = MiuAiConversation.forTesting(
        keyReader: () => 'test-only',
        enabledReader: () => true,
        personaReader: () => '叫我阿明',
        lengthReader: () => 3,
        thinkingReader: () => 'high',
        petPreferences: preferences,
        client: client);
    addTearDown(chat.dispose);
    addTearDown(preferences.dispose);

    await chat.send('嗨');
    expect(client.sentPersona, contains('Miu Luna'));
    expect(client.sentPersona, contains('叫我阿明'));
    await preferences.set(character: 'void', proactiveEnabled: true);
    client.reply = '给自己倒杯水吧。还有很多事等着一起搞定！';
    expect(await chat.generateProactive(), '给自己倒杯水吧。');
    expect(client.sentPersona, contains('Miu Void'));
    expect(client.sentPersona, contains('叫我阿明'));
    expect(client.sentLength, 1);
    expect(client.sentThinking, 'none');
    expect(client.sentTurns.last.content, contains('应用的定时陪伴请求'));
    expect(chat.messages.where((message) => message.fromUser).single.text, '嗨');
    expect(chat.messages.first.text, '给自己倒杯水吧。');
    expect(await chat.generateProactive(), isNull);
    expect(chat.messages.where((message) => message.text == '给自己倒杯水吧。'),
        hasLength(1));
  });

  test('disabled, unconfigured, busy and failed proactive requests stay silent',
      () async {
    final options = <String, String>{};
    final preferences = MiuPetPreferences.forTesting(
        read: (key) => options[key] ?? '',
        write: (key, value) async => options[key] = value);
    final client = _FakeDeepSeek();
    var enabled = false;
    String? key;
    final chat = MiuAiConversation.forTesting(
        keyReader: () => key,
        enabledReader: () => enabled,
        personaReader: () => '',
        lengthReader: () => 1,
        petPreferences: preferences,
        client: client);
    addTearDown(chat.dispose);
    addTearDown(preferences.dispose);
    expect(await chat.generateProactive(), isNull);
    await preferences.set(proactiveEnabled: true);
    expect(await chat.generateProactive(), isNull);
    enabled = true;
    expect(await chat.generateProactive(), isNull);
    expect(client.calls, 0);
    key = 'test-only';
    client.pending = Completer<String>();
    final request = chat.generateProactive();
    var staleBubble = false;
    chat.addListener(() {
      // A host attaching during a request must see its type on completion too.
      if (!chat.busy && !chat.proactiveRequest) staleBubble = true;
    });
    expect(await chat.generateProactive(), isNull);
    expect(client.calls, 1);
    client.pending!.completeError(const MiuAiRequestError('网络暂时不可用'));
    expect(await request, isNull);
    expect(chat.busy, isFalse);
    expect(chat.proactiveRequest, isFalse);
    expect(staleBubble, isFalse);
    expect(chat.messages, isEmpty);
  });

  test('AI off, role change and proactive off invalidate in-flight replies',
      () async {
    final options = <String, String>{};
    final preferences = MiuPetPreferences.forTesting(
        read: (key) => options[key] ?? '',
        write: (key, value) async => options[key] = value);
    final client = _FakeDeepSeek();
    var enabled = true;
    final chat = MiuAiConversation.forTesting(
        keyReader: () => 'test-only',
        enabledReader: () => enabled,
        personaReader: () => '',
        lengthReader: () => 1,
        petPreferences: preferences,
        client: client);
    addTearDown(chat.dispose);
    addTearDown(preferences.dispose);
    await preferences.set(proactiveEnabled: true);
    for (final change in ['ai', 'role', 'proactive']) {
      enabled = true;
      client.pending = Completer<String>();
      final request = chat.generateProactive();
      if (change == 'ai') {
        chat.invalidateProactive();
        enabled = false;
      } else if (change == 'role') {
        await preferences.set(character: 'void');
      } else {
        await preferences.set(proactiveEnabled: false);
        await preferences.set(proactiveEnabled: true);
      }
      client.pending!.complete('先休息一小会儿吧。');
      expect(await request, isNull, reason: change);
      expect(chat.messages, isEmpty, reason: change);
    }
  });
}
