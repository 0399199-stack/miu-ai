import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_ai_chat.dart';
import 'package:flutter_hbb/desktop/widgets/miu_deepseek_client.dart';

class _FakeDeepSeek extends MiuDeepSeekClient {
  int calls = 0;
  List<MiuAiTurn> sentTurns = [];

  @override
  Future<String> streamReply({
    required String apiKey,
    required String persona,
    required int replyLength,
    required List<MiuAiTurn> turns,
    required void Function(String) onPartial,
  }) async {
    calls++;
    sentTurns = turns;
    onPartial('你好');
    return '你好';
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
      client: client,
    );
    addTearDown(chat.dispose);

    await chat.send('嗨');
    expect(client.calls, 1);
    expect(chat.messages.where((m) => m.text == '你好'), hasLength(1));
    expect(client.sentTurns.last.role, 'user');
    expect(client.sentTurns.last.content, '嗨');

    enabled = false;
    await chat.send('不要发送');
    expect(client.calls, 1);
    expect(chat.messages.first.text, contains('已关闭'));
  });
}
