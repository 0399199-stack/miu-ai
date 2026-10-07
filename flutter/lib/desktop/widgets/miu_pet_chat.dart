import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:image/image.dart' as img;
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart' as win32;
import 'miu_ai_chat.dart';

import 'miu_glass.dart';

const _imagePrefix = 'miu:image/jpeg;base64,';
const _maxImageBytes = 64 * 1024;

Duration? _computerIdleTime() {
  if (!Platform.isWindows) return null;
  final lastInput = calloc<win32.LASTINPUTINFO>();
  try {
    lastInput.ref.cbSize = sizeOf<win32.LASTINPUTINFO>();
    if (win32.GetLastInputInfo(lastInput) == 0) return null;
    return Duration(milliseconds:
        (win32.GetTickCount() - lastInput.ref.dwTime) & 0xffffffff);
  } finally {
    calloc.free(lastInput);
  }
}

Uint8List? _imageBytes(String text) {
  if (!text.startsWith(_imagePrefix) ||
      text.length > _imagePrefix.length + 88000) return null;
  try {
    final bytes = base64Decode(text.substring(_imagePrefix.length));
    if (bytes.length > _maxImageBytes) return null;
    final info = img.JpegDecoder().startDecode(bytes);
    if (info == null ||
        info.width > 640 ||
        info.height > 640 ||
        info.width < 1 ||
        info.height < 1) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<String> _encodeImage(Uint8List input) async {
  if (input.length > 6 * 1024 * 1024) {
    throw const FormatException('图片不能超过 6 MB');
  }
  final decoder = img.findDecoderForData(input);
  final info = decoder?.startDecode(input);
  if (info == null ||
      info.width > 4096 ||
      info.height > 4096 ||
      info.width < 1 ||
      info.height < 1) {
    throw const FormatException('无法读取图片或图片尺寸过大');
  }
  final source = decoder!.decode(input);
  if (source == null) {
    throw const FormatException('无法读取图片');
  }
  for (final side in [640, 480, 360, 280]) {
    final scale = math.min(1.0, side / math.max(source.width, source.height));
    final reduced = scale < 1
        ? img.copyResize(source,
            width: math.max(1, (source.width * scale).round()),
            height: math.max(1, (source.height * scale).round()))
        : source;
    final jpeg = img.encodeJpg(reduced, quality: side >= 480 ? 60 : 48);
    if (jpeg.length <= _maxImageBytes) {
      return '$_imagePrefix${base64Encode(jpeg)}';
    }
  }
  throw const FormatException('图片压缩后仍过大，请选择另一张图片');
}

OverlayEntry showMiuChatPanel(
    BuildContext context, FFI ffi, VoidCallback onClose) {
  final entry = OverlayEntry(
      builder: (_) => LayoutBuilder(
            builder: (_, constraints) => _MiuFloatingChat(
              chatModel: ffi.chatModel,
              keyForPeer: MessageKey(ffi.id, ChatModel.clientModeID),
              viewportSize: constraints.biggest,
              onClose: onClose,
            ),
          ));
  Overlay.of(context).insert(entry);
  return entry;
}

class _MiuFloatingChat extends StatefulWidget {
  const _MiuFloatingChat({
    required this.chatModel,
    required this.keyForPeer,
    required this.viewportSize,
    required this.onClose,
  });

  final ChatModel chatModel;
  final MessageKey keyForPeer;
  final Size viewportSize;
  final VoidCallback onClose;

  @override
  State<_MiuFloatingChat> createState() => _MiuFloatingChatState();
}

class _MiuFloatingChatState extends State<_MiuFloatingChat> {
  Offset? _position;

  @override
  Widget build(BuildContext context) {
    final width = math.min(360.0, widget.viewportSize.width - 20);
    final height = math.min(460.0, widget.viewportSize.height - 20);
    final position = _position ??
        Offset(math.max(10, widget.viewportSize.width - width - 22), 62);
    return Stack(children: [
      Positioned(
        left: position.dx,
        top: position.dy
            .clamp(10, math.max(10, widget.viewportSize.height - height)),
        width: width,
        height: height,
        child: MiuGlass(
          padding: EdgeInsets.zero,
          radius: 28,
          child: Column(children: [
            GestureDetector(
              onPanUpdate: (details) => setState(() {
                _position = Offset(
                  (position.dx + details.delta.dx).clamp(
                      10, math.max(10, widget.viewportSize.width - width - 10)),
                  (position.dy + details.delta.dy).clamp(10,
                      math.max(10, widget.viewportSize.height - height - 10)),
                );
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
                child: Row(children: [
                  const Icon(Icons.smart_toy_rounded, color: Color(0xFF657BE9)),
                  const SizedBox(width: 9),
                  const Expanded(
                      child: Text('Miu 消息',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: '关闭消息',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
            ),
            Expanded(
                child: MiuChatView(
              chatModel: widget.chatModel,
              keyForPeer: widget.keyForPeer,
            )),
          ]),
        ),
      ),
    ]);
  }
}

class MiuChatView extends StatefulWidget {
  const MiuChatView({
    Key? key,
    required this.chatModel,
    required this.keyForPeer,
  }) : super(key: key);

  final ChatModel chatModel;
  final MessageKey keyForPeer;

  @override
  State<MiuChatView> createState() => _MiuChatViewState();
}

class _MiuChatViewState extends State<MiuChatView> {
  final _controller = TextEditingController();
  String? _error;
  bool _sendingImage = false;

  @override
  void initState() {
    super.initState();
    widget.chatModel.addListener(_markRead);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void didUpdateWidget(covariant MiuChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatModel != widget.chatModel) {
      oldWidget.chatModel.removeListener(_markRead);
      widget.chatModel.addListener(_markRead);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  void _markRead() {
    if (!mounted || widget.chatModel.miuUnreadCount(widget.keyForPeer) == 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.chatModel.markMiuRead(widget.keyForPeer);
    });
  }

  @override
  void dispose() {
    widget.chatModel.removeListener(_markRead);
    _controller.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.chatModel.sendMiuMessage(widget.keyForPeer, text)) {
      _controller.clear();
      setState(() => _error = null);
    } else {
      setState(() => _error = '当前连接已断开，消息未发送');
    }
  }

  Future<void> _sendImage() async {
    if (_sendingImage) return;
    final peerKey = widget.keyForPeer;
    setState(() {
      _sendingImage = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (!mounted || widget.keyForPeer != peerKey) return;
      final file = picked?.files.single;
      if (file == null) return;
      if (file.size > 6 * 1024 * 1024 || file.bytes == null) {
        throw const FormatException('图片不能超过 6 MB 或无法读取');
      }
      final text = await _encodeImage(file.bytes!);
      if (!mounted || widget.keyForPeer != peerKey) return;
      if (!widget.chatModel.sendMiuMessage(peerKey, text)) {
        throw const FormatException('当前连接已断开，图片未发送');
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _error = error.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  Future<void> _openImage(Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? saveStatus;
        bool saveSucceeded = false;
        return StatefulBuilder(builder: (dialogContext, updateDialog) {
          final size = MediaQuery.sizeOf(dialogContext);
          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22)),
            child: SizedBox(
              width: math.min(680, size.width - 24),
              height: math.min(680, size.height - 24),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                  child: Row(children: [
                    const Expanded(
                      child: Text('查看图片',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                if (saveStatus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(saveStatus!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: saveSucceeded
                                ? const Color(0xFF16765B)
                                : const Color(0xFFD94A61))),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Expanded(
                      child: Text('双指或滚轮缩放',
                          style: TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          final path = await FilePicker.platform.saveFile(
                            dialogTitle: '保存聊天图片',
                            fileName:
                                'MiuAI-${DateTime.now().millisecondsSinceEpoch}.jpg',
                            type: FileType.custom,
                            allowedExtensions: ['jpg'],
                          );
                          if (path == null) return;
                          await File(path).writeAsBytes(bytes, flush: true);
                          if (dialogContext.mounted) {
                            updateDialog(() {
                              saveStatus = '已保存到 $path';
                              saveSucceeded = true;
                            });
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            updateDialog(() {
                              saveStatus = '保存失败：$error';
                              saveSucceeded = false;
                            });
                          }
                        }
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('保存到本机'),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.chatModel,
      builder: (context, _) {
        final messages =
            widget.chatModel.messages[widget.keyForPeer]?.chatMessages ??
                const <ChatMessage>[];
        return Column(children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text('向对方打个招呼吧',
                        style: TextStyle(color: Color(0xFF7C89A5))))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final own = message.user.id == widget.chatModel.me.id;
                      final bytes = _imageBytes(message.text);
                      return Align(
                        alignment:
                            own ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 245),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: bytes == null
                              ? const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 9)
                              : const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: own
                                ? const Color(0xFF657BE9)
                                : Colors.white.withOpacity(0.83),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: bytes == null
                              ? SelectableText(
                                  message.text.startsWith(_imagePrefix)
                                      ? '无法显示这张图片'
                                      : message.text,
                                  style: TextStyle(
                                      color: own
                                          ? Colors.white
                                          : const Color(0xFF263252)))
                              : Tooltip(
                                  message: '点击查看或保存图片',
                                  child: InkWell(
                                    onTap: () => _openImage(bytes),
                                    borderRadius: BorderRadius.circular(13),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(13),
                                      child: Image.memory(bytes,
                                          width: 220,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Text('图片无法显示')),
                                    ),
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFD94A61), fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 12),
            child: Row(children: [
              IconButton(
                tooltip: '发送图片（压缩后最大 64 KB）',
                onPressed: _sendingImage ? null : _sendImage,
                icon: _sendingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined),
              ),
              Expanded(
                  child: TextField(
                controller: _controller,
                maxLength: 1000,
                maxLines: 1,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: '发送消息',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.72),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              )),
              IconButton(
                tooltip: '发送',
                onPressed: _sendText,
                icon: const Icon(Icons.arrow_upward_rounded,
                    color: Color(0xFF657BE9)),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

class MiuPetHost extends StatefulWidget {
  const MiuPetHost({
    Key? key,
    required this.chatModel,
    required this.keyForPeer,
    required this.onExpanded,
    this.chatAvailable = true,
  }) : super(key: key);

  final ChatModel chatModel;
  final MessageKey keyForPeer;
  final Future<void> Function(bool) onExpanded;
  final bool chatAvailable;

  @override
  State<MiuPetHost> createState() => _MiuPetHostState();
}

class _MiuPetHostState extends State<MiuPetHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();
  bool _expanded = false;
  bool _showHumanChat = false;
  bool _hovered = false;
  int _mood = 0;
  int _lastUnread = 0;
  bool _wasAiBusy = false;
  DateTime _lastActivity = DateTime.now();
  Timer? _reactionTimer;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _lastUnread = widget.chatAvailable
        ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
    widget.chatModel.addListener(_onChatChanged);
    _wasAiBusy = MiuAiConversation.instance.busy;
    MiuAiConversation.instance.addListener(_onAiChanged);
    _idleTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _expanded || _hovered ||
          (_reactionTimer?.isActive ?? false)) return;
      final unread = widget.chatAvailable
          ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
      final quiet = DateTime.now().difference(_lastActivity);
      final computerIdle = _computerIdleTime();
      var mood = 0;
      if (MiuAiConversation.instance.busy) {
        mood = 3;
      } else if (unread > 0) {
        mood = quiet > const Duration(seconds: 60)
            ? 9
            : unread >= 3 ? 8 : 3;
      } else if (computerIdle != null &&
          computerIdle > const Duration(minutes: 10)) {
        mood = 4;
      } else if (computerIdle != null &&
          computerIdle < const Duration(seconds: 10) &&
          DateTime.now().second % 15 < 3) {
        mood = 1;
      }
      if (mood != _mood) setState(() => _mood = mood);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpanded(false);
    });
  }

  @override
  void didUpdateWidget(covariant MiuPetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatModel != widget.chatModel) {
      oldWidget.chatModel.removeListener(_onChatChanged);
      widget.chatModel.addListener(_onChatChanged);
    }
    _lastUnread = widget.chatAvailable
        ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
  }

  void _onChatChanged() {
    final unread = widget.chatAvailable
        ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
    if (unread > _lastUnread) {
      _react(5, const Duration(seconds: 3));
    } else if (unread != _lastUnread) {
      _lastActivity = DateTime.now();
      setState(() {});
    }
    _lastUnread = unread;
  }

  void _onAiChanged() {
    final busy = MiuAiConversation.instance.busy;
    if (busy && !_wasAiBusy) {
      _react(3, const Duration(seconds: 2));
    } else if (!busy && _wasAiBusy) {
      _react(7, const Duration(seconds: 3));
    }
    _wasAiBusy = busy;
  }

  void _react(int mood, Duration duration) {
    _reactionTimer?.cancel();
    _lastActivity = DateTime.now();
    setState(() => _mood = mood);
    _reactionTimer = Timer(duration, () {
      if (!mounted) return;
      final unread = widget.chatAvailable
          ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
      setState(() => _mood = _hovered ? 2 : unread > 0 ? 3 : 0);
    });
  }

  @override
  void dispose() {
    widget.chatModel.removeListener(_onChatChanged);
    MiuAiConversation.instance.removeListener(_onAiChanged);
    _reactionTimer?.cancel();
    _idleTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  void _toggleChat() {
    _reactionTimer?.cancel();
    _lastActivity = DateTime.now();
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _showHumanChat = widget.chatAvailable &&
            widget.chatModel.miuUnreadCount(widget.keyForPeer) > 0;
      }
      _mood = _expanded ? 1 : 0;
    });
    widget.onExpanded(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.chatAvailable
        ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          if (_expanded)
            Positioned(
              top: 5,
              left: 5,
              right: 5,
              bottom: 163,
              child: MiuGlass(
                padding: EdgeInsets.zero,
                radius: 24,
                child: Column(children: [
                  GestureDetector(
                    onPanStart: (_) => windowManager.startDragging(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 9, 2),
                      child: Row(children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 16, color: Color(0xFF657BE9)),
                        const SizedBox(width: 7),
                        const Expanded(child: Text('Miu',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF31427B)))),
                        if (widget.chatAvailable) ...[
                          TextButton(
                            onPressed: () => setState(() => _showHumanChat = false),
                            child: Text('和 Miu 聊', style: TextStyle(
                              color: _showHumanChat ? const Color(0xFF7380A0) : const Color(0xFF4569D9))),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _showHumanChat = true),
                            child: Text('A 消息', style: TextStyle(
                              color: _showHumanChat ? const Color(0xFF4569D9) : const Color(0xFF7380A0))),
                          ),
                        ],
                        IconButton(
                          tooltip: '收起消息',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: _toggleChat,
                          icon: const Icon(Icons.close_rounded,
                              color: Color(0xFF31427B)),
                        ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: _showHumanChat && widget.chatAvailable
                        ? MiuChatView(
                            chatModel: widget.chatModel,
                            keyForPeer: widget.keyForPeer)
                        : const MiuAiChatView(),
                  ),
                ]),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 196,
            height: 192,
            child: Tooltip(
              message: '点我聊天 · 双击爱心 · 长按撒娇 · 拖动可移动',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onTap: _toggleChat,
                onDoubleTap: () => _react(6, const Duration(seconds: 2)),
                onLongPress: () => _react(7, const Duration(seconds: 2)),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) {
                    _lastActivity = DateTime.now();
                    setState(() {
                      _hovered = true;
                      if (!(_reactionTimer?.isActive ?? false)) _mood = 2;
                    });
                  },
                  onExit: (_) {
                    _lastActivity = DateTime.now();
                    setState(() {
                      _hovered = false;
                      if (!(_reactionTimer?.isActive ?? false)) {
                        _mood = widget.chatAvailable &&
                                widget.chatModel.miuUnreadCount(widget.keyForPeer) > 0
                            ? 3 : 0;
                      }
                    });
                  },
                  child: AnimatedScale(
                    scale: _hovered ? 1.045 : 1,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: AnimatedBuilder(
                      animation: _motion,
                      builder: (_, __) {
                        final phase = _motion.value * math.pi * 2;
                        final lift = _mood == 7
                            ? -5 * (1 - math.cos(phase * 2))
                            : -3.5 * (1 - math.cos(phase));
                        final sway = 2.5 * math.sin(phase);
                        final tilt = (_mood == 2 ? 0.04 : _mood == 8 ? -0.04 : 0.0) +
                            0.027 * math.sin(phase);
                        final scale = 1 + 0.02 * math.sin(phase - 0.5);
                        double blinkAt(double center, double width) =>
                            Curves.easeInOut.transform(
                                (1 - (_motion.value - center).abs() / width)
                                    .clamp(0.0, 1.0));
                        final blink = math.max(
                            blinkAt(0.24, 0.026), blinkAt(0.78, 0.036));
                        return Transform.translate(
                          offset: Offset(sway, lift),
                          child: Transform.rotate(
                            angle: tilt,
                            child: Transform.scale(
                              scale: scale,
                              child: _MiuPetFace(
                                mood: _mood,
                                blink: blink,
                                gaze: 1.6 * math.sin(phase),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_expanded)
            Positioned(
              left: 8,
              right: 8,
              top: 3,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: unread > 0 ? 1 : 0,
                  duration: const Duration(milliseconds: 280),
                  child: AnimatedSlide(
                    offset: unread > 0 ? Offset.zero : const Offset(0, -0.35),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: AnimatedBuilder(
                      animation: _motion,
                      builder: (_, child) => Transform.scale(
                        scale: 1 + 0.035 * (1 + math.sin(_motion.value * math.pi * 2)),
                        child: child,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [
                            Color(0xFF4D8FFB), Color(0xFF766AF2),
                          ]),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white, width: 1.4),
                          boxShadow: const [BoxShadow(
                            color: Color(0x665373E8), blurRadius: 16, offset: Offset(0, 5),
                          )],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mark_chat_unread_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Flexible(child: Text(
                            unread > 1 ? '${unread > 99 ? '99+' : unread} 条新消息' : '收到新消息',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 12, fontWeight: FontWeight.w700),
                          )),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiuPetFace extends StatelessWidget {
  const _MiuPetFace({required this.mood, required this.blink, required this.gaze});

  final int mood;
  final double blink;
  final double gaze;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 196,
      height: 192,
      child: Center(
        child: SizedBox.square(
          dimension: 178,
          child: Stack(fit: StackFit.expand, children: [
            RepaintBoundary(child: Image.asset('assets/miu_cat_head.png',
                filterQuality: FilterQuality.medium)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: SizedBox.expand(
                key: ValueKey(mood),
                child: CustomPaint(painter: _MiuCatExpression(mood, blink, gaze)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MiuCatExpression extends CustomPainter {
  const _MiuCatExpression(this.mood, this.blink, this.gaze);

  final int mood;
  final double blink;
  final double gaze;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 126, size.height / 126);
    const navy = Color(0xFF143571);
    final line = Paint()
      ..color = navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    void eye(double x, bool closed, {double look = 0}) {
      if (closed || blink > 0.92) {
        final curve = Path()
          ..moveTo(x - 9, 74)
          ..quadraticBezierTo(x, 82, x + 9, 74);
        canvas.drawPath(curve, line);
        return;
      }
      final area = Rect.fromCenter(
          center: Offset(x, 75), width: 18, height: 24 * (1 - blink) + 2);
      canvas.drawOval(area.inflate(1.5), Paint()..color = Colors.white);
      canvas.drawOval(
          area,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF12295D), Color(0xFF2059BC), Color(0xFF39C8F4)],
            ).createShader(area));
      canvas.drawCircle(Offset(x + look + gaze, 69), 4,
          Paint()..color = const Color(0xFF102D68));
      canvas.drawCircle(Offset(x - 3 + look + gaze, 69), 2.6,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x + 4, 79), 1.2,
          Paint()..color = Colors.white.withOpacity(0.9));
    }

    eye(45, mood == 4 || mood == 7,
        look: mood == 2 ? 2 : mood == 6 ? -2 : 0);
    eye(81, mood == 1 || mood == 4 || mood == 7,
        look: mood == 6 ? -2 : mood == 8 ? 2 : 0);

    if (mood == 3 || mood == 8 || mood == 9) {
      canvas.drawPath(
          Path()
            ..moveTo(73, 57)
            ..quadraticBezierTo(81, mood == 3 ? 54 : 62, 89, 58),
          line..strokeWidth = 2.3);
    }
    if (mood == 2 || mood == 5) {
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(63, 96), width: 8, height: 10),
          Paint()..color = const Color(0xFFDF7086));
    } else if (mood == 3 || mood == 8) {
      canvas.drawPath(
          Path()
            ..moveTo(58, 98)
            ..quadraticBezierTo(63, 94, 68, 98),
          line..strokeWidth = 2);
    } else if (mood == 9) {
      canvas.drawPath(
          Path()
            ..moveTo(56, 100)
            ..quadraticBezierTo(63, 91, 70, 100),
          line..strokeWidth = 2.5);
    } else if (mood == 4 || mood == 6) {
      canvas.drawPath(
          Path()
            ..moveTo(57, 94)
            ..quadraticBezierTo(63, 100, 69, 94),
          line..strokeWidth = 2.5);
    } else {
      final mouth = Path()
        ..moveTo(54, 92)
        ..quadraticBezierTo(63, 105, 72, 92)
        ..quadraticBezierTo(63, 97, 54, 92)
        ..close();
      canvas.drawPath(mouth, Paint()..color = const Color(0xFFE74D71));
      canvas.drawPath(mouth, line..strokeWidth = 1.4);
    }

    final accent = Paint()
      ..color = mood == 6 ? const Color(0xFFF47EAB) : const Color(0xFF368DF3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (mood == 2 || mood == 8) {
      canvas.drawPath(
          Path()
            ..moveTo(98, 29)
            ..quadraticBezierTo(106, 23, 109, 30)
            ..quadraticBezierTo(111, 35, 105, 39),
          accent);
      canvas.drawCircle(const Offset(105, 43), 1.4, accent..style = PaintingStyle.fill);
    } else if (mood == 4) {
      for (var i = 0; i < 2; i++) {
        final x = 98.0 + i * 7;
        canvas.drawPath(
            Path()
              ..moveTo(x, 31)
              ..lineTo(x + 5, 31)
              ..lineTo(x, 37)
              ..lineTo(x + 5, 37),
            accent);
      }
    } else if (mood == 5) {
      canvas.drawLine(const Offset(105, 27), const Offset(105, 36), accent);
      canvas.drawCircle(const Offset(105, 41), 1.7, accent..style = PaintingStyle.fill);
    } else if (mood == 6) {
      final heart = Path()
        ..moveTo(105, 41)
        ..cubicTo(94, 35, 99, 27, 105, 32)
        ..cubicTo(111, 27, 116, 35, 105, 41)
        ..close();
      canvas.drawPath(heart, accent..style = PaintingStyle.fill);
    } else if (mood == 7) {
      final star = Path()
        ..moveTo(105, 27)
        ..lineTo(107, 32)
        ..lineTo(112, 34)
        ..lineTo(107, 36)
        ..lineTo(105, 41)
        ..lineTo(103, 36)
        ..lineTo(98, 34)
        ..lineTo(103, 32)
        ..close();
      canvas.drawPath(star, accent..style = PaintingStyle.fill);
    } else if (mood == 9) {
      canvas.drawPath(
          Path()
            ..moveTo(90, 82)
            ..quadraticBezierTo(95, 89, 90, 92)
            ..quadraticBezierTo(86, 89, 90, 82),
          Paint()..color = const Color(0xFF64CFFF));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiuCatExpression oldDelegate) =>
      mood != oldDelegate.mood || blink != oldDelegate.blink ||
      gaze != oldDelegate.gaze;
}
