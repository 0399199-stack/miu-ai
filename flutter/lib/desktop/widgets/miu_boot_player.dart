import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path/path.dart' as path;

class MiuBootSettings {
  const MiuBootSettings({this.color = '#48AAFF', this.autoPlay = true});
  final String color;
  final bool autoPlay;

  static MiuBootSettings? parse(Object? value) {
    if (value is! Map ||
        value['color'] is! String ||
        (value['color'] as String).length != 7 ||
        !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value['color'] as String) ||
        value['autoPlay'] is! bool) return null;
    return MiuBootSettings(
        color: (value['color'] as String).toUpperCase(),
        autoPlay: value['autoPlay'] as bool);
  }

  Map<String, dynamic> toJson() => {'color': color, 'autoPlay': autoPlay};
}

class MiuBootPlayer {
  MiuBootPlayer._()
      : _read = (() => bind.mainGetLocalOption(key: _key)),
        _write = ((value) => bind.mainSetLocalOption(key: _key, value: value)),
        _launch = _launchNative;

  @visibleForTesting
  MiuBootPlayer.forTesting({
    required String Function() read,
    required Future<void> Function(String) write,
    required Future<bool> Function(String) launch,
  })  : _read = read,
        _write = write,
        _launch = launch;

  static final instance = MiuBootPlayer._();
  static const _key = 'miu-boot-settings';
  final String Function() _read;
  final Future<void> Function(String) _write;
  final Future<bool> Function(String) _launch;

  MiuBootSettings get settings {
    try {
      return MiuBootSettings.parse(jsonDecode(_read())) ??
          const MiuBootSettings();
    } catch (_) {
      return const MiuBootSettings();
    }
  }

  Future<bool> save(Object? value) async {
    final next = MiuBootSettings.parse(value);
    if (next == null) return false;
    try {
      await _write(jsonEncode(next.toJson()));
      return settings.color == next.color && settings.autoPlay == next.autoPlay;
    } catch (_) {
      return false;
    }
  }

  Future<bool> play({bool atLogin = false}) async {
    final current = settings;
    if (atLogin && !current.autoPlay) return false;
    return _launch(current.color);
  }

  static String get _executable => path.join(
      File(Platform.resolvedExecutable).parent.path, 'MiuBoot', 'MiuBoot.exe');

  Future<bool> available() async {
    if (!Platform.isWindows || !await File(_executable).exists()) return false;
    try {
      final result = await Process.run(_executable, ['--check'])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launchNative(String color) async {
    Process? process;
    StreamSubscription<String>? output;
    StreamSubscription<List<int>>? errors;
    final started = Completer<bool>();
    try {
      process = await Process.start(_executable, ['--color', color]);
      output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line == 'STARTED' && !started.isCompleted) started.complete(true);
      }, onError: (_) {
        if (!started.isCompleted) started.complete(false);
      });
      errors = process.stderr.listen((_) {});
      process.exitCode.then((_) {
        if (!started.isCompleted) started.complete(false);
      });
      final result = await started.future.timeout(const Duration(seconds: 9));
      if (!result) process.kill();
      return result;
    } catch (_) {
      process?.kill();
      return false;
    } finally {
      await output?.cancel();
      await errors?.cancel();
    }
  }
}
