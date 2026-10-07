import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'miu_glass.dart';
import 'miu_image_transfer.dart';

OverlayEntry showMiuSendImagePanel(
  BuildContext context,
  FFI ffi,
  VoidCallback onClose, {
  required Future<Uint8List> Function() readClipboardPng,
}) {
  final entry = OverlayEntry(
      builder: (_) => LayoutBuilder(
          builder: (_, constraints) => _MiuSendImagePanel(
                ffi: ffi,
                onClose: onClose,
                readClipboardPng: readClipboardPng,
                viewport: constraints.biggest,
              )));
  Overlay.of(context).insert(entry);
  return entry;
}

class _MiuSendImagePanel extends StatefulWidget {
  const _MiuSendImagePanel({
    required this.ffi,
    required this.onClose,
    required this.readClipboardPng,
    required this.viewport,
  });

  final FFI ffi;
  final VoidCallback onClose;
  final Future<Uint8List> Function() readClipboardPng;
  final Size viewport;

  @override
  State<_MiuSendImagePanel> createState() => _MiuSendImagePanelState();
}

class _MiuSendImagePanelState extends State<_MiuSendImagePanel> {
  File? _selected;
  File? _temporary;
  Offset? _position;
  String? _message;
  bool _sending = false;
  double _progress = 0;

  @override
  void dispose() {
    if (!_sending) _deleteTemporary();
    super.dispose();
  }

  void _deleteTemporary() {
    final file = _temporary;
    _temporary = null;
    if (file != null) unawaited(file.delete().catchError((_) => file));
  }

  Future<void> _setFile(File file, {bool temporary = false}) async {
    if (_sending) return;
    try {
      await validateMiuImageFile(file);
      if (!mounted) return;
      _deleteTemporary();
      setState(() {
        _selected = file;
        _temporary = temporary ? file : null;
        _message = null;
      });
    } catch (error) {
      if (temporary) unawaited(file.delete().catchError((_) => file));
      if (mounted) setState(() => _message = _explain(error));
    }
  }

  Future<void> _pickFile() async {
    if (_sending) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final filePath = picked?.files.single.path;
    if (filePath != null && mounted) await _setFile(File(filePath));
  }

  Future<void> _pasteImage() async {
    if (_sending) return;
    try {
      final png = await widget.readClipboardPng();
      if (png.isEmpty || png.length > miuImageMaxBytes) {
        throw const FormatException('剪贴板图片为空或超过 25 MB');
      }
      final file = File(path.join(Directory.systemTemp.path,
          'MiuAI-Clipboard-${const Uuid().v4()}.png'));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) {
        await file.delete();
        return;
      }
      await _setFile(file, temporary: true);
    } catch (error) {
      if (mounted) setState(() => _message = _explain(error));
    }
  }

  Future<void> _send() async {
    final file = _selected;
    if (_sending || file == null) return;
    setState(() {
      _sending = true;
      _progress = 0;
      _message = null;
    });
    try {
      await sendAndOpenMiuImage(
        controller: widget.ffi,
        source: file,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _message = '图片已发送，B 机已打开');
    } catch (error) {
      if (mounted) setState(() => _message = _explain(error));
    } finally {
      if (mounted) setState(() => _sending = false);
      if (!mounted) _deleteTemporary();
    }
  }

  String _explain(Object error) => error
      .toString()
      .replaceFirst('FormatException: ', '')
      .replaceFirst('Bad state: ', '');

  @override
  Widget build(BuildContext context) {
    final width = math.min(376.0, widget.viewport.width - 20);
    final height = math.min(430.0, widget.viewport.height - 20);
    final position = _position ??
        Offset(math.max(10, widget.viewport.width - width - 20), 62);
    return Stack(children: [
      Positioned(
        left: position.dx,
        top: position.dy
            .clamp(10, math.max(10, widget.viewport.height - height - 10)),
        width: width,
        height: height,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                _pasteImage,
          },
          child: Focus(
            autofocus: true,
            child: MiuGlass(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              radius: 26,
              child: Column(children: [
                GestureDetector(
                  onPanUpdate: (details) => setState(() {
                    _position = Offset(
                      (position.dx + details.delta.dx).clamp(
                          10, math.max(10, widget.viewport.width - width - 10)),
                      (position.dy + details.delta.dy).clamp(10,
                          math.max(10, widget.viewport.height - height - 10)),
                    );
                  }),
                  child: Row(children: [
                    const Icon(Icons.image_rounded, color: Color(0xFF657BE9)),
                    const SizedBox(width: 9),
                    const Expanded(
                        child: Text('发送并打开图片',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700))),
                    IconButton(
                        tooltip: '关闭',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded)),
                  ]),
                ),
                const SizedBox(height: 8),
                Expanded(
                    child: DropTarget(
                  onDragDone: (details) {
                    if (details.files.isNotEmpty) {
                      unawaited(_setFile(File(details.files.first.path)));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.46),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD6E2FA)),
                    ),
                    child: _selected == null
                        ? const Center(
                            child: Text('拖入图片，或选择文件 / 粘贴图片',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF7485A8))))
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Image.file(_selected!,
                                      cacheWidth: 600, fit: BoxFit.contain),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(path.basename(_selected!.path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                  ),
                )),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton.icon(
                      onPressed: _sending ? null : _pickFile,
                      icon: const Icon(Icons.folder_open_rounded, size: 17),
                      label: const Text('选择文件')),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                      onPressed: _sending ? null : _pasteImage,
                      icon: const Icon(Icons.content_paste_rounded, size: 17),
                      label: const Text('粘贴')),
                ]),
                if (_sending) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_message!,
                        maxLines: 2, style: const TextStyle(fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                      onPressed: _sending || _selected == null ? null : _send,
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('发送并打开')),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
