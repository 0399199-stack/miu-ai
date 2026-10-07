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
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();
  bool _expanded = false;
  int _mood = 0;
  int _lastUnread = 0;
  Timer? _reactionTimer;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _lastUnread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
    widget.chatModel.addListener(_onChatChanged);
    _idleTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted && !_expanded) setState(() => _mood = (_mood + 1) % 10);
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
    _lastUnread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
  }

  void _onChatChanged() {
    final unread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
    if (unread > _lastUnread) {
      _reactionTimer?.cancel();
      setState(() => _mood = 5);
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
    _idleTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _expanded = !_expanded;
      _mood = (_mood + 1) % 10;
    });
    widget.onExpanded(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.chatModel.miuUnreadCount(widget.keyForPeer);
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
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(18, 12, 18, 5),
                      child: Row(children: [
                        Icon(Icons.chat_bubble_outline_rounded,
                            size: 16, color: Color(0xFF657BE9)),
                        SizedBox(width: 7),
                        Text('Miu 消息',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF31427B))),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: MiuChatView(
                        chatModel: widget.chatModel,
                        keyForPeer: widget.keyForPeer),
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
              message: '点我聊天 · 拖动可移动',
              child: GestureDetector(
                onPanStart: (_) => windowManager.startDragging(),
                onTap: _toggleChat,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedBuilder(
                    animation: _motion,
                    builder: (_, __) {
                      final phase = _motion.value * math.pi * 2;
                      final lively = _mood == 0 || _mood == 5 || _mood == 7;
                      final lift = lively
                          ? -7 * math.sin(phase).abs()
                          : -4 * math.sin(phase);
                      final sway = 2.5 * math.sin(phase + _mood * 0.6);
                      final tilt = (_mood == 2 ? 0.06 : _mood == 8 ? -0.06 : 0.0) +
                          0.035 * math.sin(phase);
                      final scale = 1 + 0.025 * math.sin(phase - 0.5);
                      final blink = (1.0 -
                              (_motion.value - 0.82).abs() / 0.035)
                          .clamp(0.0, 1.0)
                          .toDouble();
                      return Transform.translate(
                        offset: Offset(sway, lift),
                        child: Transform.rotate(
                          angle: tilt,
                          child: Transform.scale(
                            scale: scale,
                            child: Stack(children: [
                              _MiuPetFace(mood: _mood, blink: blink),
                              if (unread > 0)
                                const Positioned(
                                  right: 20,
                                  top: 22,
                                  child: CircleAvatar(
                                    radius: 5,
                                    backgroundColor: Color(0xFFEF709C),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
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
  const _MiuPetFace({required this.mood, required this.blink});

  final int mood;
  final double blink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 196,
      height: 192,
      child: Center(
        child: SizedBox.square(
          dimension: 178,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset('assets/miu_cat_head.png', filterQuality: FilterQuality.medium),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: SizedBox.expand(
                key: ValueKey(mood),
                child: CustomPaint(painter: _MiuCatExpression(mood, blink)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MiuCatExpression extends CustomPainter {
  const _MiuCatExpression(this.mood, this.blink);

  final int mood;
  final double blink;

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
      canvas.drawCircle(Offset(x + look, 69), 4,
          Paint()..color = const Color(0xFF102D68));
      canvas.drawCircle(Offset(x - 3 + look, 69), 2.6,
          Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x + 4, 79), 1.2,
          Paint()..color = Colors.white.withOpacity(0.9));
    }

    eye(45, mood == 4 || mood == 7 || mood == 9,
        look: mood == 2 ? 2 : mood == 6 ? -2 : 0);
    eye(81, mood == 1 || mood == 4 || mood == 7 || mood == 9,
        look: mood == 6 ? -2 : mood == 8 ? 2 : 0);

    if (mood == 3 || mood == 8) {
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
    } else if (mood == 4 || mood == 6 || mood == 9) {
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
            ..moveTo(106, 40)
            ..lineTo(106, 29)
            ..lineTo(112, 27),
          accent);
      canvas.drawOval(
          Rect.fromCenter(center: const Offset(103, 41), width: 5, height: 3),
          accent..style = PaintingStyle.fill);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiuCatExpression oldDelegate) =>
      mood != oldDelegate.mood || blink != oldDelegate.blink;
}
