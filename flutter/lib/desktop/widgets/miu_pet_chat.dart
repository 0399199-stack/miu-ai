import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

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
import 'miu_chat_send_shortcut.dart';
import 'miu_pet_avatar.dart';
import 'miu_pet_preferences.dart';
import 'miu_pet_proactive.dart';

import 'miu_glass.dart';

const _imagePrefix = 'miu:image/jpeg;base64,';
const _maxImageBytes = 64 * 1024;

bool _desktopUnlocked() {
  if (!Platform.isWindows) return false;
  final desktop = win32.OpenInputDesktop(
      0, 0, win32.DESKTOP_ACCESS_FLAGS.DESKTOP_READOBJECTS);
  if (desktop == 0) return false;
  final name = calloc<Uint16>(256);
  final length = calloc<Uint32>();
  try {
    return win32.GetUserObjectInformation(desktop,
            win32.USER_OBJECT_INFORMATION_INDEX.UOI_NAME, name, 512, length) != 0 &&
        name.cast<Utf16>().toDartString() == 'Default';
  } finally {
    calloc.free(name);
    calloc.free(length);
    DynamicLibrary.open('user32.dll')
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseDesktop')(desktop);
  }
}

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
        left: position.dx
            .clamp(10, math.max(10, widget.viewportSize.width - width - 10)),
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
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 4),
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
                  child: MiuChatSendShortcut(
                controller: _controller,
                onSend: _sendText,
                child: TextField(
                controller: _controller,
                maxLength: 1000,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
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
              ))),
              IconButton(
                tooltip: '发送（Enter）',
                onPressed: _sendText,
                icon: const Icon(Icons.arrow_upward_rounded,
                    color: Color(0xFF657BE9)),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Enter 发送 · Shift+Enter 换行',
                style: TextStyle(fontSize: 11, color: Color(0xFF697994))),
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
    this.preferences,
  }) : super(key: key);

  final ChatModel chatModel;
  final MessageKey keyForPeer;
  final Future<void> Function(bool) onExpanded;
  final bool chatAvailable;
  final MiuPetPreferences? preferences;

  @override
  State<MiuPetHost> createState() => _MiuPetHostState();
}

class _MiuPetHostState extends State<MiuPetHost> {
  bool _expanded = false;
  bool _showHumanChat = false;
  bool _hovered = false;
  int _mood = 0;
  int _lastUnread = 0;
  bool _wasAiBusy = false;
  int _lastAiLines = 0;
  String? _aiNotice;
  bool _noticeHuman = true;
  bool _proactiveRequest = false;
  String? _proactiveNotice;
  late final MiuPetPreferences _preferences;
  late final MiuPetProactiveTimer _proactiveTimer;
  Timer? _proactiveNoticeTimer;
  DateTime _lastActivity = DateTime.now();
  Timer? _reactionTimer;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? MiuPetPreferences.instance;
    _preferences.refresh();
    _preferences.addListener(_onPreferencesChanged);
    _proactiveTimer = MiuPetProactiveTimer(onDue: _requestProactive);
    _updateProactive();
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

  void _updateProactive() => _proactiveTimer.update(
      _preferences.proactiveEnabled && MiuAiConversation.instance.enabled);

  void _onPreferencesChanged() {
    _updateProactive();
    _proactiveNoticeTimer?.cancel();
    setState(() => _proactiveNotice = null);
  }

  bool get _canShowProactive => mounted && !_expanded &&
      _preferences.proactiveEnabled && MiuAiConversation.instance.enabled &&
      !MiuAiConversation.instance.busy && _aiNotice == null &&
      (!widget.chatAvailable ||
          widget.chatModel.miuUnreadCount(widget.keyForPeer) == 0);

  Future<void> _requestProactive() async {
    if (!_canShowProactive) return;
    try {
      if (!await windowManager.isVisible() || !_desktopUnlocked() ||
          !_canShowProactive) return;
      final revision = _preferences.revision;
      _proactiveRequest = true;
      final text = await MiuAiConversation.instance.generateProactive();
      if (text == null || !_canShowProactive ||
          !await windowManager.isVisible()) return;
      if (!_canShowProactive || revision != _preferences.revision ||
          !_desktopUnlocked()) return;
      setState(() => _proactiveNotice = text);
      _react(1, const Duration(seconds: 2));
      _proactiveNoticeTimer?.cancel();
      _proactiveNoticeTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _proactiveNotice = null);
      });
    } catch (_) {
      // A hidden/unavailable desktop skips this opportunity until the next slot.
    } finally {
      _proactiveRequest = false;
    }
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
      _noticeHuman = true;
      _react(5, const Duration(seconds: 3));
    } else if (unread != _lastUnread) {
      _lastActivity = DateTime.now();
      setState(() {});
    }
    _lastUnread = unread;
  }

  void _onAiChanged() {
    _updateProactive();
    final busy = MiuAiConversation.instance.busy;
    final messages = MiuAiConversation.instance.messages;
    final lines =
        messages.isEmpty ? 0 : (messages.first.text.length / 30).ceil();
    if (_proactiveRequest || MiuAiConversation.instance.proactiveRequest) {
      _wasAiBusy = busy;
      return;
    }
    if (busy && !_wasAiBusy) {
      _react(3, const Duration(seconds: 2));
    } else if (!busy && _wasAiBusy) {
      if ((!_expanded || _showHumanChat) && messages.isNotEmpty &&
          !messages.first.fromUser && messages.first.text.isNotEmpty) {
        _aiNotice = messages.first.text;
        _noticeHuman = false;
      }
      _react(7, const Duration(seconds: 3));
    } else if (_expanded && lines != _lastAiLines) {
      setState(() {});
    }
    _lastAiLines = lines;
    _wasAiBusy = busy;
  }

  void _react(int mood, Duration duration) {
    _reactionTimer?.cancel();
    _lastActivity = DateTime.now();
    setState(() => _mood = mood);
    _reactionTimer = Timer(duration + const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      final unread = widget.chatAvailable
          ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
      setState(() => _mood = _hovered ? 2 : unread > 0 ? 3 : 0);
    });
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferencesChanged);
    _proactiveTimer.dispose();
    _proactiveNoticeTimer?.cancel();
    if (_proactiveRequest) MiuAiConversation.instance.invalidateProactive();
    widget.chatModel.removeListener(_onChatChanged);
    MiuAiConversation.instance.removeListener(_onAiChanged);
    _reactionTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }

  void _toggleChat() {
    _proactiveNoticeTimer?.cancel();
    _reactionTimer?.cancel();
    _lastActivity = DateTime.now();
    setState(() {
      _proactiveNotice = null;
      _expanded = !_expanded;
      if (_expanded) {
        _showHumanChat = widget.chatAvailable &&
            widget.chatModel.miuUnreadCount(widget.keyForPeer) > 0 &&
            (_noticeHuman || _aiNotice == null);
        if (!_showHumanChat) _aiNotice = null;
      }
      _mood = _expanded ? 1 : 0;
    });
    widget.onExpanded(_expanded);
  }

  void _openNotice(bool human) {
    _proactiveNoticeTimer?.cancel();
    _reactionTimer?.cancel();
    _lastActivity = DateTime.now();
    setState(() {
      _proactiveNotice = null;
      _expanded = true;
      _showHumanChat = human;
      if (!human) _aiNotice = null;
      _mood = 1;
    });
    widget.onExpanded(true);
  }

  String _humanPreview() {
    final messages = widget.chatModel.messages[widget.keyForPeer]?.chatMessages;
    for (final message in messages ?? const <ChatMessage>[]) {
      if (message.user.id == widget.chatModel.me.id) continue;
      return message.text.startsWith(_imagePrefix)
          ? '收到图片'
          : message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '收到新消息';
  }

  Widget _chatTab(String label, bool selected, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor:
            selected ? const Color(0xFF637BE8) : Colors.transparent,
        foregroundColor: selected ? Colors.white : const Color(0xFF52648F),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = widget.chatAvailable
        ? widget.chatModel.miuUnreadCount(widget.keyForPeer) : 0;
    final showNotice = unread > 0 || _aiNotice != null || _proactiveNotice != null;
    final humanNotice = unread > 0 && (_noticeHuman || _aiNotice == null);
    final noticeText = humanNotice ? _humanPreview() : _aiNotice ?? _proactiveNotice ?? '';
    final isVoid = _preferences.character == 'void';
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          if (_expanded)
            Positioned(
              top: 5,
              left: 8,
              right: 8,
              bottom: 166,
              child: LayoutBuilder(builder: (context, constraints) {
                final charsPerLine =
                    math.max(20, ((constraints.maxWidth - 110) / 14).floor());
                final recentLines = MiuAiConversation.instance.messages
                    .take(3)
                    .fold<int>(
                        0,
                        (lines, message) =>
                            lines +
                            (message.text.length / charsPerLine).ceil());
                final height = math.min(constraints.maxHeight,
                    350.0 + math.min(190, recentLines * 18));
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xF8F8FAFF), Color(0xF4EAF0FC)],
                            ),
                          ),
                          child: Column(children: [
                            GestureDetector(
                              onPanStart: (_) => windowManager.startDragging(),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 10, 4),
                                child: Row(children: [
                                  const Icon(Icons.chat_bubble_outline_rounded,
                                      size: 16, color: Color(0xFF657BE9)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE5EAF8),
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _chatTab(
                                                'Miu AI',
                                                !_showHumanChat,
                                                () => setState(() {
                                                  _showHumanChat = false;
                                                  _aiNotice = null;
                                                })),
                                            if (widget.chatAvailable)
                                              _chatTab(
                                                  'Terminal',
                                                  _showHumanChat,
                                                  () => setState(() =>
                                                      _showHumanChat = true)),
                                          ]),
                                    ),
                                  )),
                                  Container(
                                    decoration: const BoxDecoration(
                                        color: Color(0xFFF4E8EE),
                                        shape: BoxShape.circle),
                                    child: IconButton(
                                      tooltip: '关闭聊天',
                                      iconSize: 20,
                                      visualDensity: VisualDensity.compact,
                                      onPressed: _toggleChat,
                                      icon: const Icon(Icons.close_rounded,
                                          color: Color(0xFF9A435B)),
                                    ),
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
                    ),
                  ),
                );
              }),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            width: 196,
            height: 192,
            child: Tooltip(
              message: '${isVoid ? 'Miu Void' : 'Miu Luna'} · 点我聊天 · 双击互动 · 长按互动 · 拖动可移动',
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
                    scale: showNotice && !_expanded ? .82 : 1,
                    alignment: Alignment.bottomCenter,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: MiuPetAvatar(mood: _mood, character: _preferences.character),
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
                ignoring: !showNotice,
                child: GestureDetector(
                  key: const ValueKey('miu-pet-message-notice'),
                  onTap: () => _openNotice(humanNotice),
                  child: AnimatedOpacity(
                    opacity: showNotice ? 1 : 0,
                    duration: const Duration(milliseconds: 240),
                    child: AnimatedSlide(
                      offset: showNotice ? Offset.zero : const Offset(0, -.35),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: isVoid
                              ? const [Color(0xFFFDF2F5), Color(0xFFF2E7ED)]
                              : const [Color(0xFFF5FBFF), Color(0xFFEAF1FF)]),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFB9D5FA)),
                          boxShadow: const [BoxShadow(
                            color: Color(0x405373E8), blurRadius: 14, offset: Offset(0, 4),
                          )],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.mark_chat_unread_rounded,
                                size: 13, color: Color(0xFF4879D9)),
                            const SizedBox(width: 5),
                            Expanded(child: Text(humanNotice ? 'Terminal' : isVoid ? 'Miu Void' : 'Miu Luna',
                                style: const TextStyle(color: Color(0xFF4879D9),
                                    fontSize: 11, fontWeight: FontWeight.w700))),
                            if (humanNotice && unread > 1)
                              Text('${unread > 99 ? '99+' : unread} 条',
                                  style: const TextStyle(color: Color(0xFF4879D9), fontSize: 10)),
                            const Icon(Icons.open_in_full_rounded,
                                size: 11, color: Color(0xFF7C92B8)),
                          ]),
                          const SizedBox(height: 4),
                          Text(noticeText, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF263A60),
                                  fontSize: 12, height: 1.3)),
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
