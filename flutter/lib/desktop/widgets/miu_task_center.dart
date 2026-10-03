import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Dialog;
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:get/get.dart';

import 'miu_glass.dart';
import 'miu_remote_task_executor.dart';

enum _TaskKind { website, program, command }

enum _TaskState { sending, sent, completed, failed }

class _TaskRecord {
  _TaskRecord(this.kind, this.value) : time = DateTime.now();

  final _TaskKind kind;
  final String value;
  final DateTime time;
  _TaskState state = _TaskState.sending;
  String detail = '正在发送到远程电脑';
  String output = '';
}

OverlayEntry showMiuTaskCenter(
    BuildContext context, FFI ffi, VoidCallback onClose) {
  final entry = OverlayEntry(
    builder: (_) => LayoutBuilder(
      builder: (_, constraints) => Stack(children: [
        _MiuTaskCenter(
            ffi: ffi, onClose: onClose, viewportSize: constraints.biggest),
      ]),
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}

class _MiuTaskCenter extends StatefulWidget {
  const _MiuTaskCenter(
      {required this.ffi, required this.onClose, required this.viewportSize});

  final FFI ffi;
  final VoidCallback onClose;
  final Size viewportSize;

  @override
  State<_MiuTaskCenter> createState() => _MiuTaskCenterState();
}

class _MiuTaskCenterState extends State<_MiuTaskCenter> {
  final _input = TextEditingController();
  final _records = <_TaskRecord>[];
  _TaskKind _kind = _TaskKind.website;
  Offset? _position;
  String? _error;
  bool _sending = false;

  bool get _canSendTask =>
      !widget.ffi.closed &&
      widget.ffi.connType == ConnType.defaultConn &&
      widget.ffi.ffiModel.keyboard &&
      widget.ffi.ffiModel.isPeerWindows;

  bool get _canRestart =>
      _canSendTask && widget.ffi.ffiModel.permissions['restart'] != false;

  void _restart() {
    if (_sending || !_canRestart) return;
    final ffi = widget.ffi;
    showRestartRemoteDevice(
        ffi.ffiModel.pi, ffi.id, ffi.sessionId, ffi.dialogManager);
  }

  void _togglePrivacyMode() {
    final ffi = widget.ffi;
    final state = PrivacyModeState.find(ffi.id);
    if (_sending ||
        ffi.closed ||
        ffi.connType != ConnType.defaultConn ||
        !ffi.ffiModel.isPeerWindows ||
        ffi.ffiModel.viewOnly ||
        (state.isEmpty &&
            (!ffi.ffiModel.keyboard ||
                !ffi.ffiModel.pi.features.privacyMode ||
                ffi.ffiModel.permissions['privacy_mode'] == false))) {
      return;
    }
    final options = toolbarPrivacyMode(state, context, ffi.id, ffi);
    if (options.isEmpty) return;
    final selected = state.isNotEmpty
        ? options.firstWhere((option) => option.value,
            orElse: () => options.first)
        : options.first;
    selected.onChanged?.call(!selected.value);
  }

  String _label(_TaskKind kind) {
    switch (kind) {
      case _TaskKind.website:
        return translate('Open website');
      case _TaskKind.program:
        return translate('Open program');
      case _TaskKind.command:
        return translate('Run command');
    }
  }

  IconData _icon(_TaskKind kind) {
    switch (kind) {
      case _TaskKind.website:
        return Icons.language_rounded;
      case _TaskKind.program:
        return Icons.apps_rounded;
      case _TaskKind.command:
        return Icons.terminal_rounded;
    }
  }

  String _hint() {
    switch (_kind) {
      case _TaskKind.website:
        return 'https://example.com';
      case _TaskKind.program:
        return 'notepad.exe';
      case _TaskKind.command:
        return 'dir C:\\';
    }
  }

  String? _validate(String value) {
    if (value.isEmpty || value.contains('\n') || value.contains('\r')) {
      return translate('Enter one line');
    }
    if (_kind == _TaskKind.website) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme.toLowerCase()) ||
          uri.host.isEmpty) {
        return translate('Enter an HTTP(S) address');
      }
    }
    return null;
  }

  void _update(_TaskRecord record, _TaskState state, String detail,
      [String output = '']) {
    if (!mounted) return;
    setState(() {
      record.state = state;
      record.detail = detail;
      record.output = output;
      _sending = false;
    });
  }

  Future<void> _run() async {
    if (_sending) return;
    final value = _input.text.trim();
    final error = _validate(value);
    if (error != null || !_canSendTask) {
      setState(() => _error = error ?? '当前连接不能发送任务');
      return;
    }

    final record = _TaskRecord(_kind, value);
    setState(() {
      _error = null;
      _sending = true;
      _records.insert(0, record);
      if (_records.length > 8) _records.removeLast();
    });

    try {
      final kind = switch (_kind) {
        _TaskKind.website => MiuRemoteTaskKind.website,
        _TaskKind.program => MiuRemoteTaskKind.program,
        _TaskKind.command => MiuRemoteTaskKind.command,
      };
      final result = await executeMiuRemoteTask(
          controller: widget.ffi, kind: kind, value: value);
      if (result.launchOnly) {
        final target = result.processId == null
            ? '远端已发起打开；页面或程序是否完成仍需查看远程画面'
            : '远端已启动进程 ${result.processId}；运行结果仍需查看远程画面';
        _update(
            record,
            result.succeeded ? _TaskState.sent : _TaskState.failed,
            result.succeeded ? target : '启动失败 · 退出码 ${result.exitCode}',
            result.output);
      } else {
        _update(
            record,
            result.succeeded ? _TaskState.completed : _TaskState.failed,
            '命令已结束 · 退出码 ${result.exitCode}'
            '${result.outputTruncated ? ' · 输出已截断' : ''}',
            result.output);
      }
    } catch (e) {
      _update(record, _TaskState.failed, '发送失败：$e');
    }
  }

  Future<void> _showOutput(_TaskRecord record) => showDialog<void>(
        context: context,
        builder: (dialogContext) => material.Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 480),
            child: MiuGlass(
              radius: 28,
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Expanded(
                      child: Text('执行输出',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: '复制输出',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: record.output)),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(record.output),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.viewportSize;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = const Color(0xFF617BE9);
    final width = math.max(0.0, math.min(520.0, size.width - 24));
    final height = math.max(0.0, math.min(480.0, size.height - 24));
    final maxX = math.max(0.0, size.width - width);
    final maxY = math.max(0.0, size.height - height);
    final left = (_position?.dx ?? maxX / 2).clamp(0.0, maxX);
    final top = (_position?.dy ?? maxY / 2).clamp(0.0, maxY);
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(30),
        clipBehavior: Clip.antiAlias,
        color: dark ? const Color(0xFF111A2D) : const Color(0xFFF8FAFF),
        child: MiuBackdrop(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MiuGlass(
              radius: 26,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => setState(() {
                      _position = Offset(
                        ((_position?.dx ?? left) + details.delta.dx)
                            .clamp(0.0, maxX),
                        ((_position?.dy ?? top) + details.delta.dy)
                            .clamp(0.0, maxY),
                      );
                    }),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('任务中心',
                                style: TextStyle(
                                    fontSize: 21, fontWeight: FontWeight.w700)),
                            Text('发送到 ${widget.ffi.id}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: translate('Close'),
                        onPressed: _sending ? null : widget.onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        const SizedBox(height: 22),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final kind in _TaskKind.values)
                              ChoiceChip(
                                label: Text(_label(kind)),
                                avatar: Icon(_icon(kind),
                                    size: 17,
                                    color: kind == _kind ? accent : null),
                                selected: kind == _kind,
                                onSelected: (_) => setState(() {
                                  _kind = kind;
                                  _error = null;
                                  _input.clear();
                                }),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _input,
                          autofocus: true,
                          maxLines: 1,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(1200)
                          ],
                          keyboardType: _kind == _TaskKind.website
                              ? TextInputType.url
                              : TextInputType.text,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _run(),
                          decoration: InputDecoration(
                            hintText: _hint(),
                            errorText: _error,
                            prefixIcon: Icon(_icon(_kind)),
                            filled: true,
                            fillColor:
                                Colors.white.withOpacity(dark ? 0.07 : 0.58),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(17),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _kind == _TaskKind.command
                              ? '命令通过已授权的远程终端执行，完成后显示退出码和输出。'
                              : '将尝试在 B 机启动；启动成功不代表页面加载或程序运行完成。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _sending ? null : _run,
                            icon: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.arrow_upward_rounded,
                                    size: 18),
                            label: Text(_sending ? '发送中' : translate('Run')),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 23, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  _sending || !_canRestart ? null : _restart,
                              icon: const Icon(Icons.restart_alt_rounded,
                                  size: 18),
                              label: const Text('重启 B 机'),
                            ),
                            Obx(() {
                              final state =
                                  PrivacyModeState.find(widget.ffi.id);
                              final active = state.isNotEmpty;
                              final model = widget.ffi.ffiModel;
                              final available = !widget.ffi.closed &&
                                  widget.ffi.connType == ConnType.defaultConn &&
                                  model.isPeerWindows &&
                                  !model.viewOnly &&
                                  (active ||
                                      (model.keyboard &&
                                          model.pi.features.privacyMode &&
                                          model.permissions['privacy_mode'] !=
                                              false));
                              return OutlinedButton.icon(
                                onPressed: _sending || !available
                                    ? null
                                    : _togglePrivacyMode,
                                icon: Icon(active
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded),
                                label: Text(active ? '关闭防窥' : '开启防窥'),
                              );
                            }),
                          ],
                        ),
                        Text('防窥效果需在 B 机实测确认。',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 20),
                        Text('当前窗口的操作',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 9),
                        SizedBox(
                          height: math.max(90.0, height - 390),
                          child: _records.isEmpty
                              ? Center(
                                  child: Text('尚无操作',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall))
                              : ListView.separated(
                                  itemCount: _records.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (_, index) {
                                    final record = _records[index];
                                    final stateIcon = switch (record.state) {
                                      _TaskState.sending => Icons.sync_rounded,
                                      _TaskState.sent => Icons.send_rounded,
                                      _TaskState.completed =>
                                        Icons.check_circle_outline_rounded,
                                      _TaskState.failed =>
                                        Icons.error_outline_rounded,
                                    };
                                    final stateColor =
                                        record.state == _TaskState.failed
                                            ? Colors.redAccent
                                            : accent;
                                    return InkWell(
                                      onTap: record.output.isEmpty
                                          ? null
                                          : () => _showOutput(record),
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 11),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withOpacity(dark ? 0.05 : 0.46),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Row(children: [
                                          Icon(stateIcon,
                                              color: stateColor, size: 20),
                                          const SizedBox(width: 11),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    '${_label(record.kind)}  ·  ${record.value}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                                Text(record.detail,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall),
                                                if (record.output.isNotEmpty)
                                                  Text(record.output,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
