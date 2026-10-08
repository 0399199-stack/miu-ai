import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_deepseek_client.dart';

void main() {
  test('default response stays to one short sentence', () {
    expect(compactMiuReply('你好呀。第二句不该出现。', 1), '你好呀。');
    expect(compactMiuReply('你好呀。可以聊聊。第三句不该出现。', 2), '你好呀。可以聊聊。');
    expect(compactMiuReply('你好呀。可以多聊一点。第三句也能看到。', 3), '你好呀。可以多聊一点。第三句也能看到。');
  });

  test('streams text with only chat context and non-thinking mode', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? body;
    String? authorization;
    final serverTask = () async {
      final request = await server.first;
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      body = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"你好"}}]}\n\n'));
      await request.response.flush();
      request.response.add(
          utf8.encode('data: {"choices":[{"delta":{"content":"呀"}}]}\n\n'));
      request.response.add(utf8.encode('data: [DONE]\n\n'));
      await request.response.close();
    }();
    final partial = <String>[];
    try {
      final answer = await MiuDeepSeekClient(
              endpoint:
                  Uri.parse('http://127.0.0.1:${server.port}/chat/completions'))
          .streamReply(
        apiKey: 'sk-test-only',
        persona: '',
        replyLength: 1,
        turns: const [MiuAiTurn('user', '你好')],
        onPartial: partial.add,
      );
      await serverTask;
      expect(answer, '你好呀');
      expect(partial, ['你好', '你好呀']);
      expect(authorization, 'Bearer sk-test-only');
      expect(body?['stream'], true);
      expect(body?['thinking'], {'type': 'disabled'});
      expect(body?['reasoning_effort'], 'none');
      expect(body?['model'], 'deepseek-flash');
      final messages = body?['messages'] as List;
      expect(messages.last, {'role': 'user', 'content': '你好'});
      expect(body.toString(), isNot(contains('image_url')));
      expect(body.toString(), isNot(contains('file_data')));
    } finally {
      await server.close(force: true);
    }
  });

  test('selected Pro model, deep thinking and detailed mode reach API',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? body;
    final serverTask = () async {
      final request = await server.first;
      body = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.add(utf8.encode(
          'data: {"choices":[{"delta":{"reasoning_content":"internal"}}]}\n\n'));
      request.response.add(utf8.encode(
          'data: {"choices":[{"delta":{"content":"第一句。第二句。第三句。"}}]}\n\n'));
      request.response.add(utf8.encode('data: [DONE]\n\n'));
      await request.response.close();
    }();
    final partial = <String>[];
    try {
      final answer = await MiuDeepSeekClient(
              endpoint:
                  Uri.parse('http://127.0.0.1:${server.port}/chat/completions'))
          .streamReply(
        apiKey: 'sk-test-only',
        persona: '',
        replyLength: 3,
        model: 'deepseek-v4-pro',
        thinking: 'high',
        turns: const [MiuAiTurn('user', '详细讲讲')],
        onPartial: partial.add,
      );
      await serverTask;
      expect(answer, '第一句。第二句。第三句。');
      expect(partial, ['第一句。第二句。第三句。']);
      expect(body?['model'], 'deepseek-v4-pro');
      expect(body?['thinking'], {'type': 'enabled'});
      expect(body?['reasoning_effort'], 'high');
      expect(body?['max_tokens'], greaterThan(4096));
      expect((body?['messages'] as List).first['content'], contains('详细回复'));
      expect(answer, isNot(contains('internal')));
    } finally {
      await server.close(force: true);
    }
  });

  test('maps insufficient balance without exposing server response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverTask = () async {
      final request = await server.first;
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 402;
      request.response.write('private upstream diagnostic');
      await request.response.close();
    }();
    try {
      await expectLater(
        MiuDeepSeekClient(
                endpoint: Uri.parse(
                    'http://127.0.0.1:${server.port}/chat/completions'))
            .streamReply(
          apiKey: 'sk-test-only',
          persona: '',
          replyLength: 1,
          turns: const [MiuAiTurn('user', '你好')],
          onPartial: (_) {},
        ),
        throwsA(isA<MiuAiRequestError>()
            .having((error) => error.message, 'message', contains('余额不足'))),
      );
      await serverTask;
    } finally {
      await server.close(force: true);
    }
  });
}
