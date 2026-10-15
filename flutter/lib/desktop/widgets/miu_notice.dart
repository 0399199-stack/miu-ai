import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

class MiuNotice {
  const MiuNotice({
    required this.title,
    required this.text,
    this.seconds = 15,
    this.sound = true,
  });

  final String title;
  final String text;
  final int seconds;
  final bool sound;

  static MiuNotice? parse(Object? value) {
    if (value is! Map ||
        value['title'] is! String ||
        value['text'] is! String ||
        value['seconds'] is! int ||
        value['sound'] is! bool) return null;
    final title = value['title'] as String;
    final text = value['text'] as String;
    final seconds = value['seconds'] as int;
    if (RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(title) ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]').hasMatch(text) ||
        title.trim().isEmpty ||
        title.trim().length > 60 ||
        text.trim().isEmpty ||
        text.trim().length > 1200 ||
        seconds < 1 ||
        seconds > 300) return null;
    return MiuNotice(
        title: title.trim(),
        text: text.trim(),
        seconds: seconds,
        sound: value['sound'] as bool);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'text': text,
        'seconds': seconds,
        'sound': sound,
      };
}

class MiuNoticeHost {
  MiuNoticeHost(this.executable);

  static final instance = MiuNoticeHost(path.join(
      File(Platform.resolvedExecutable).parent.path, 'MiuNotice.exe'));
  final String executable;
  Process? _active;
  bool _starting = false;

  Future<bool> show(MiuNotice notice) async {
    final validated = MiuNotice.parse(notice.toJson());
    if (!Platform.isWindows || validated == null || _starting) return false;
    _starting = true;
    Process? process;
    StreamSubscription<String>? output;
    StreamSubscription<List<int>>? errors;
    final shown = Completer<bool>();
    try {
      final launched = await Process.start(executable, []);
      process = launched;
      output = launched.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line == 'SHOWN' && !shown.isCompleted) shown.complete(true);
      }, onError: (_) {
        if (!shown.isCompleted) shown.complete(false);
      });
      errors = launched.stderr.listen((_) {});
      launched.exitCode.then((_) {
        if (!shown.isCompleted) shown.complete(false);
        if (identical(_active, launched)) _active = null;
      });
      launched.stdin.encoding = utf8;
      launched.stdin.writeln(jsonEncode(validated.toJson()));
      await launched.stdin.close();
      final visible = await shown.future.timeout(const Duration(seconds: 9));
      if (visible) {
        // Keep the previous notice if the replacement cannot be displayed.
        _active?.kill();
        _active = launched;
      } else {
        launched.kill();
      }
      return visible;
    } catch (_) {
      process?.kill();
      return false;
    } finally {
      await output?.cancel();
      await errors?.cancel();
      _starting = false;
    }
  }
}
