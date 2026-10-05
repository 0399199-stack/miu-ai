import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:image/image.dart' as img;
import 'package:window_manager/window_manager.dart';

import 'miu_glass.dart';

const _imagePrefix = 'miu:image/jpeg;base64,';
const _maxImageBytes = 64 * 1024;

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
                              ? Text(
                                  message.text.startsWith(_imagePrefix)
                                      ? '无法显示这张图片'
                                      : message.text,
                                  style: TextStyle(
                                      color: own
                                          ? Colors.white
                                          : const Color(0xFF263252)))
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Image.memory(bytes,
                                      width: 220,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Text('图片无法显示'))),
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
  }) : super(key: key);

  final ChatModel chatModel;
  final MessageKey keyForPeer;
  final Future<void> Function(bool) onExpanded;

  @override
  State<MiuPetHost> createState() => _MiuPetHostState();
}

class _MiuPetHostState extends State<MiuPetHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);
  bool _expanded = false;
  int _mood = 0;
  int _lastUnread = 0;
  Timer? _reactionTimer;

  @override
  void initState() {
    super.initState();
    _lastUnread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
    widget.chatModel.addListener(_onChatChanged);
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
    _lastUnread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
  }

  void _onChatChanged() {
    final unread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
    if (unread > _lastUnread) {
      _reactionTimer?.cancel();
      setState(() => _mood = 2);
      _reactionTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _mood = 0);
      });
    } else if (unread != _lastUnread) {
      setState(() {});
    }
    _lastUnread = unread;
  }

  @override
  void dispose() {
    widget.chatModel.removeListener(_onChatChanged);
    _reactionTimer?.cancel();
    _breathe.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _expanded = !_expanded;
      _mood = (_mood + 1) % 4;
    });
    widget.onExpanded(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(27),
              border: Border.all(color: Colors.white.withOpacity(0.9)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xF9F8FBFF), Color(0xF3E5EDFF)],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x3392A4D5), blurRadius: 24)
              ],
            ),
            child: Column(children: [
              GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
                onTap: _toggleChat,
                child: SizedBox(
                  height: _expanded ? 140 : 176,
                  child: Column(children: [
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 15, color: Color(0xFF7184EF)),
                      const SizedBox(width: 5),
                      const Text('Miu',
                          style: TextStyle(
                              color: Color(0xFF31427B),
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      if (unread > 0) const SizedBox(width: 6),
                      if (unread > 0)
                        const CircleAvatar(
                            radius: 3, backgroundColor: Color(0xFFEF709C)),
                    ]),
                    AnimatedBuilder(
                        animation: _breathe,
                        builder: (_, __) {
                          final lift = math.sin(_breathe.value * math.pi) * 5;
                          return Transform.translate(
                            offset: Offset(0, -lift),
                            child: Transform.scale(
                              scale: 1 + 0.035 * _breathe.value,
                              child: _MiuPetFace(
                                  mood: _mood,
                                  blink: _breathe.value > 0.92 &&
                                      _breathe.value < 0.97),
                            ),
                          );
                        }),
                    Text(['点我聊天', '你好呀 ✨', '收到啦', '陪你一会儿'][_mood],
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64739A))),
                  ]),
                ),
              ),
              if (_expanded)
                Expanded(
                    child: MiuChatView(
                        chatModel: widget.chatModel,
                        keyForPeer: widget.keyForPeer)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MiuPetFace extends StatelessWidget {
  const _MiuPetFace({required this.mood, required this.blink});

  final int mood;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 108,
      child: Stack(alignment: Alignment.center, children: [
        Positioned(
            top: 0,
            child: Container(
              width: 10,
              height: 18,
              decoration: BoxDecoration(
                  color: const Color(0xFF8E9CF5),
                  borderRadius: BorderRadius.circular(9)),
            )),
        Positioned(
            top: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFFB4C8FF)),
            )),
        Positioned(
            top: 15,
            child: Container(
              width: 96,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFB8E6FF),
                    Color(0xFF7D8FF4),
                    Color(0xFFB498F5)
                  ],
                ),
                border:
                    Border.all(color: Colors.white.withOpacity(0.85), width: 2),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66788EEB),
                      blurRadius: 15,
                      offset: Offset(0, 6))
                ],
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _eye(blink || mood == 2),
                      const SizedBox(width: 25),
                      _eye(blink),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                        mood == 1
                            ? 'ᴗ'
                            : mood == 3
                                ? '▽'
                                : '◡',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 25, height: 0.8)),
                  ]),
            )),
      ]),
    );
  }

  Widget _eye(bool wink) => Container(
        width: 10,
        height: wink ? 3 : 13,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(7)),
      );
}
