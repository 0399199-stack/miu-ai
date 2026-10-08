import 'dart:async';
import 'dart:convert';
import 'dart:io';

const miuDefaultPersona = '你是 Miu，一只蓝白色桌面小猫，也是由 DeepSeek 驱动的 AI 助手。'
    '温柔、机灵，偶尔调皮。默认用简体中文，口语自然，通常只回复一句，最多两句；'
    '不用客服套话、列表或重复卖萌。被问到身份时如实说明你是 AI，不假装真人。'
    '只根据当前聊天文字回复，不声称看到了屏幕、图片、文件或远控操作。';

class MiuAiTurn {
  const MiuAiTurn(this.role, this.content);

  final String role;
  final String content;
}

class MiuAiRequestError implements Exception {
  const MiuAiRequestError(this.message);

  final String message;

  @override
  String toString() => message;
}

String compactMiuReply(String text, int replyLength) {
  final maxSentences = replyLength <= 1 ? 1 : 2;
  final maxLength = replyLength <= 1
      ? 96
      : replyLength == 2
          ? 160
          : 300;
  final trimmed = text.trim();
  var sentences = 0;
  for (var i = 0; i < trimmed.length && i < maxLength; i++) {
    if ('。！？.!?'.contains(trimmed[i])) {
      sentences++;
      if (sentences >= maxSentences) return trimmed.substring(0, i + 1);
    }
  }
  return trimmed.length > maxLength
      ? '${trimmed.substring(0, maxLength).trimRight()}…'
      : trimmed;
}

class MiuDeepSeekClient {
  MiuDeepSeekClient({Uri? endpoint})
      : endpoint =
            endpoint ?? Uri.parse('https://api.deepseek.com/chat/completions');

  final Uri endpoint;

  Future<String> streamReply({
    required String apiKey,
    required String persona,
    required int replyLength,
    required List<MiuAiTurn> turns,
    required void Function(String) onPartial,
  }) async {
    if (apiKey.isEmpty || turns.isEmpty || turns.last.role != 'user') {
      throw const MiuAiRequestError('请先在 B 机设置 DeepSeek API Key');
    }
    final length = replyLength.clamp(1, 3);
    final style = switch (length) {
      1 => '这一轮只用一句简短的话回复。',
      2 => '这一轮最多用两句简短的话回复。',
      _ => '这一轮可以稍详细，但最多两句。',
    };
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '$miuDefaultPersona\n${persona.trim()}\n$style',
      },
      for (final turn in turns.skip(turns.length > 9 ? turns.length - 9 : 0))
        {'role': turn.role, 'content': turn.content},
    ];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request =
          await client.postUrl(endpoint).timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.add(utf8.encode(jsonEncode({
        'model': 'deepseek-flash',
        'thinking': {'type': 'disabled'},
        'messages': messages,
        'max_tokens': switch (length) { 1 => 128, 2 => 220, _ => 380 },
        'stream': true,
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw MiuAiRequestError(switch (response.statusCode) {
          401 => 'DeepSeek API Key 无效，请在 B 机重新设置',
          402 => 'DeepSeek 余额不足，请充值后重试',
          429 => '消息有点频繁，请稍后再试',
          _ => 'DeepSeek 暂时不可用，请稍后再试',
        });
      }
      final text = StringBuffer();
      var done = false;
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45))) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') {
          done = true;
          break;
        }
        if (data.isEmpty) continue;
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) continue;
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final delta = choices.first['delta'];
        final part = delta is Map ? delta['content'] : null;
        if (part is String && part.isNotEmpty) {
          text.write(part);
          onPartial(compactMiuReply(text.toString(), length));
        }
      }
      if (!done || text.toString().trim().isEmpty) {
        throw const MiuAiRequestError('Miu 暂时没能回复，请再试一次');
      }
      return compactMiuReply(text.toString(), length);
    } on MiuAiRequestError {
      rethrow;
    } on SocketException {
      throw const MiuAiRequestError('网络暂时不可用，请稍后再试');
    } on TimeoutException {
      throw const MiuAiRequestError('DeepSeek 响应超时，请稍后再试');
    } catch (_) {
      throw const MiuAiRequestError('Miu 暂时没能回复，请稍后再试');
    } finally {
      client.close(force: true);
    }
  }
}
