import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uuid/uuid.dart';

enum MiuRemoteTaskKind { website, program, command }

class MiuRemoteTaskResult {
  const MiuRemoteTaskResult({
    required this.kind,
    required this.exitCode,
    required this.output,
    required this.outputTruncated,
    this.processId,
  });

  final MiuRemoteTaskKind kind;
  final int exitCode;
  final String output;
  final bool outputTruncated;
  final int? processId;

  bool get succeeded => exitCode == 0;
  bool get launchOnly => kind != MiuRemoteTaskKind.command;
}

/// Runs one task through RustDesk's existing terminal-scoped connection.
/// A successful URL/program result confirms launch dispatch, not page load or app completion.
Future<MiuRemoteTaskResult> executeMiuRemoteTask({
  required FFI controller,
  required MiuRemoteTaskKind kind,
  required String value,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (controller.closed || controller.id.isEmpty) {
    throw StateError('Remote connection is closed');
  }
  if (controller.connType != ConnType.defaultConn ||
      controller.ffiModel.viewOnly ||
      !controller.ffiModel.isPeerWindows) {
    throw StateError('Tasks require an interactive Windows control session');
  }
  if (value.isEmpty ||
      value.contains('\r') ||
      value.contains('\n') ||
      value.length > 1200) {
    throw FormatException('Task must be one line of at most 1200 characters');
  }
  if (kind == MiuRemoteTaskKind.website) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw FormatException('Website must be an HTTP(S) URL');
    }
  }
  final token = bind.sessionGetConnToken(sessionId: controller.sessionId);
  if (token == null || token.isEmpty) {
    throw StateError(
        'A password-authenticated connection is required for tasks');
  }

  const terminalId = 0;
  final taskId = const Uuid().v4().replaceAll('-', '');
  final parser = _TaskOutputParser(taskId, kind);
  final command = _encodedPowerShellCommand(taskId, kind, value);
  final taskFfi = FFI(null);
  final completion = Completer<MiuRemoteTaskResult>();
  Timer? timer;
  bool finished = false;
  bool requestedOpen = false;
  bool opened = false;
  bool sent = false;

  void fail(Object error) {
    if (finished) return;
    finished = true;
    completion.completeError(error);
  }

  taskFfi.onTaskConnectionError =
      (message) => fail(StateError('Remote task connection failed: $message'));
  taskFfi.onTerminalReady = () {
    if (finished || requestedOpen) return;
    requestedOpen = true;
    unawaited(bind
        .sessionOpenTerminal(
            sessionId: taskFfi.sessionId,
            terminalId: terminalId,
            rows: 24,
            cols: 120)
        .catchError(fail));
  };
  taskFfi.onTerminalResponse = (event) {
    if (finished || event['terminal_id']?.toString() != '$terminalId') return;
    switch (event['type']) {
      case 'opened':
        if (event['success'] != true && event['success'] != 'true') {
          fail(
              StateError('Remote terminal refused: ${event['message'] ?? ''}'));
          return;
        }
        opened = true;
        if (!sent) {
          sent = true;
          unawaited(bind
              .sessionSendTerminalInput(
                  sessionId: taskFfi.sessionId,
                  terminalId: terminalId,
                  data: '$command\r')
              .catchError(fail));
        }
        break;
      case 'data':
        try {
          final data = base64Decode(event['data'] as String);
          final result = parser.add(data);
          if (result != null) {
            finished = true;
            completion.complete(result);
          }
        } catch (error) {
          fail(StateError('Invalid terminal output: $error'));
        }
        break;
      case 'closed':
        fail(StateError('Remote shell closed before task completion'));
        break;
      case 'error':
        fail(StateError('Remote terminal error: ${event['message'] ?? ''}'));
        break;
    }
  };

  timer = Timer(timeout,
      () => fail(TimeoutException('Remote task did not finish', timeout)));
  try {
    taskFfi.start(controller.id, isTerminal: true, connToken: token);
    return await completion.future;
  } finally {
    finished = true;
    timer.cancel();
    taskFfi.onTaskConnectionError = null;
    taskFfi.onTerminalReady = null;
    taskFfi.onTerminalResponse = null;
    if (opened) {
      try {
        await bind.sessionCloseTerminal(
            sessionId: taskFfi.sessionId, terminalId: terminalId);
      } catch (_) {}
    }
    await taskFfi.close();
  }
}

String _encodedPowerShellCommand(
    String taskId, MiuRemoteTaskKind kind, String value) {
  final encodedValue = base64Encode(utf8.encode(value));
  final action = switch (kind) {
    MiuRemoteTaskKind.command =>
      r'& $env:ComSpec /d /s /c $task' '\n' r'$exitCode = [int]$LASTEXITCODE',
    MiuRemoteTaskKind.website =>
      r'Start-Process -FilePath $task -ErrorAction Stop | Out-Null',
    MiuRemoteTaskKind.program =>
      r'$process = Start-Process -FilePath $task -PassThru -ErrorAction Stop'
          '\n'
          r'if ($null -ne $process) { $launchedPid = [int]$process.Id }',
  };
  final script = '''
\$ErrorActionPreference = 'Stop'
\$task = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedValue'))
[Console]::Out.WriteLine('__MIU_TASK_BEGIN_${taskId}__')
\$exitCode = 0
\$launchedPid = 0
try {
$action
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  \$exitCode = 1
}
[Console]::Out.WriteLine('__MIU_TASK_END_${taskId}__:' + \$exitCode + ':' + \$launchedPid + '__')
''';
  final utf16 = Uint8List(script.codeUnits.length * 2);
  for (var i = 0; i < script.codeUnits.length; i++) {
    utf16[i * 2] = script.codeUnits[i] & 0xff;
    utf16[i * 2 + 1] = script.codeUnits[i] >> 8;
  }
  return 'powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ${base64Encode(utf16)}';
}

class _TaskOutputParser {
  _TaskOutputParser(String id, this.kind)
      : _begin = ascii.encode('__MIU_TASK_BEGIN_${id}__'),
        _end = ascii.encode('__MIU_TASK_END_${id}__:');

  static const maxOutputBytes = 256 * 1024;
  final MiuRemoteTaskKind kind;
  final List<int> _begin;
  final List<int> _end;
  final _pending = <int>[];
  final _output = <int>[];
  bool _begun = false;
  bool _truncated = false;

  MiuRemoteTaskResult? add(List<int> chunk) {
    _pending.addAll(chunk);
    if (!_begun) {
      final start = _find(_pending, _begin);
      if (start < 0) {
        _keepTail(_begin.length - 1);
        return null;
      }
      _pending.removeRange(0, start + _begin.length);
      _begun = true;
    }
    final end = _find(_pending, _end);
    if (end < 0) {
      _appendOutput(_pending.length - _end.length + 1);
      return null;
    }
    _appendOutput(end);
    final suffix = ascii.decode(_pending.skip(_end.length).take(40).toList(),
        allowInvalid: true);
    final match = RegExp(r'^(-?\d+):(-?\d+)__').firstMatch(suffix);
    if (match == null) {
      if (suffix.length > 32) {
        throw FormatException('Invalid task completion marker');
      }
      return null;
    }
    final exitCode = int.parse(match.group(1)!);
    final pid = int.parse(match.group(2)!);
    return MiuRemoteTaskResult(
      kind: kind,
      exitCode: exitCode,
      output: utf8.decode(_output, allowMalformed: true).trim(),
      outputTruncated: _truncated,
      processId: pid > 0 ? pid : null,
    );
  }

  void _appendOutput(int count) {
    if (count <= 0) return;
    final available = maxOutputBytes - _output.length;
    if (count > available) _truncated = true;
    if (available > 0) {
      _output.addAll(_pending.take(count < available ? count : available));
    }
    _pending.removeRange(0, count);
  }

  void _keepTail(int length) {
    if (_pending.length > length) {
      _pending.removeRange(0, _pending.length - length);
    }
  }

  static int _find(List<int> haystack, List<int> needle) {
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      var matches = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i;
    }
    return -1;
  }
}
