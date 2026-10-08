import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:draggable_float_widget/draggable_float_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

import '../consts.dart';
import '../common.dart';
import '../common/widgets/overlay.dart';
import '../desktop/widgets/miu_ai_credentials.dart';
import '../desktop/widgets/miu_ai_history.dart';
import '../main.dart';
import 'model.dart';

class MessageKey {
  final String peerId;
  final int connId;
  bool get isOut => connId == ChatModel.clientModeID;

  MessageKey(this.peerId, this.connId);

  @override
  bool operator ==(other) {
    return other is MessageKey &&
        other.peerId == peerId &&
        other.isOut == isOut;
  }

  @override
  int get hashCode => peerId.hashCode ^ isOut.hashCode;
}

class MessageBody {
  ChatUser chatUser;
  List<ChatMessage> chatMessages;
  MessageBody(this.chatUser, this.chatMessages);

  void insert(ChatMessage cm) {
    chatMessages.insert(0, cm);
  }

  void clear() {
    chatMessages.clear();
  }
}

const _miuControlPrefix = '\u001eMiuAI-control-v1:';
final _miuImageName =
    RegExp(r'^MiuAI-[0-9a-f]{32}\.(?:png|jpg|jpeg|webp|gif|bmp)$');

bool isMiuImageInHome(String remotePath, String userHome) {
  if (!path.windows.isAbsolute(userHome) ||
      !path.windows.isAbsolute(remotePath) ||
      path.windows.split(remotePath).contains('..') ||
      !_miuImageName.hasMatch(path.windows.basename(remotePath))) return false;
  final expected = path.windows.join(
      userHome, path.windows.basename(remotePath));
  return path.windows.normalize(remotePath).toLowerCase() ==
      path.windows.normalize(expected).toLowerCase();
}

class ChatModel with ChangeNotifier {
  static final clientModeID = -1;

  OverlayEntry? chatIconOverlayEntry;
  OverlayEntry? chatWindowOverlayEntry;

  bool isConnManager = false;

  RxBool isWindowFocus = true.obs;
  BlockableOverlayState _blockableOverlayState = BlockableOverlayState();
  final Rx<VoiceCallStatus> _voiceCallStatus = Rx(VoiceCallStatus.notStarted);

  Rx<VoiceCallStatus> get voiceCallStatus => _voiceCallStatus;

  TextEditingController textController = TextEditingController();
  RxInt mobileUnreadSum = 0.obs;
  MessageKey? latestReceivedKey;

  Offset chatWindowPosition = Offset(20, 80);

  void setChatWindowPosition(Offset position) {
    chatWindowPosition = position;
    notifyListeners();
  }

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  final ChatUser me = ChatUser(
    id: Uuid().v4().toString(),
    firstName: translate("Me"),
  );

  late final Map<MessageKey, MessageBody> _messages = {};
  final Map<MessageKey, int> _miuUnread = {};
  final Map<String, Completer<Map<String, dynamic>>> _miuPendingControls = {};
  bool? _miuPetVisible;
  bool? _miuPetAiEnabled;
  String? _miuPetPersona;
  int? _miuPetReplyLength;
  String? _miuPetAiModel;
  String? _miuPetAiThinking;
  List<MiuAiHistoryEntry> _miuAiHistory = [];
  int _miuHistoryEpoch = 0;

  bool? get miuPetVisible => _miuPetVisible;
  bool? get miuPetAiEnabled => _miuPetAiEnabled;
  String? get miuPetPersona => _miuPetPersona;
  int? get miuPetReplyLength => _miuPetReplyLength;
  String? get miuPetAiModel => _miuPetAiModel;
  String? get miuPetAiThinking => _miuPetAiThinking;
  List<MiuAiHistoryEntry> get miuAiHistory => List.unmodifiable(_miuAiHistory);

  int miuUnreadCount(MessageKey key) => _miuUnread[key] ?? 0;

  void markMiuRead(MessageKey key) {
    if (_miuUnread.remove(key) != null) notifyListeners();
  }

  MessageKey _currentKey = MessageKey('', -2); // -2 is invalid value
  late bool _isShowCMSidePage = false;

  Map<MessageKey, MessageBody> get messages => _messages;

  MessageKey get currentKey => _currentKey;

  bool get isShowCMSidePage => _isShowCMSidePage;

  void setOverlayState(BlockableOverlayState blockableOverlayState) {
    _blockableOverlayState = blockableOverlayState;

    _blockableOverlayState.addMiddleBlockedListener((v) {
      if (!v) {
        isWindowFocus.value = false;
        if (isWindowFocus.value) {
          isWindowFocus.toggle();
        }
      }
    });
  }

  final WeakReference<FFI> parent;

  late final SessionID sessionId;
  late FocusNode inputNode;

  ChatModel(this.parent) {
    sessionId = parent.target!.sessionId;
    inputNode = FocusNode(
      onKey: (_, event) {
        bool isShiftPressed = event.isKeyPressed(LogicalKeyboardKey.shiftLeft);
        bool isEnterPressed = event.isKeyPressed(LogicalKeyboardKey.enter);

        // don't send empty messages
        if (isEnterPressed && isEnterPressed && textController.text.isEmpty) {
          return KeyEventResult.handled;
        }

        if (isEnterPressed && !isShiftPressed) {
          final ChatMessage message = ChatMessage(
            text: textController.text,
            user: me,
            createdAt: DateTime.now(),
          );
          send(message);
          textController.clear();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
    );
  }

  ChatUser? get currentUser => _messages[_currentKey]?.chatUser;

  showChatIconOverlay({Offset offset = const Offset(200, 50)}) {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
    }
    // mobile check navigationBar
    final bar = navigationBarKey.currentWidget;
    if (bar != null) {
      if ((bar as BottomNavigationBar).currentIndex == 1) {
        return;
      }
    }

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;

    final overlay = OverlayEntry(builder: (context) {
      return DraggableFloatWidget(
        config: DraggableFloatWidgetBaseConfig(
          initPositionYInTop: false,
          initPositionYMarginBorder: 100,
          borderTopContainTopBar: true,
        ),
        child: FloatingActionButton(
          onPressed: () {
            if (chatWindowOverlayEntry == null) {
              showChatWindowOverlay();
            } else {
              hideChatWindowOverlay();
            }
          },
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: SvgPicture.asset('assets/chat2.svg'),
        ),
      );
    });
    overlayState.insert(overlay);
    chatIconOverlayEntry = overlay;
  }

  hideChatIconOverlay() {
    if (chatIconOverlayEntry != null) {
      chatIconOverlayEntry!.remove();
      chatIconOverlayEntry = null;
    }
  }

  showChatWindowOverlay({Offset? chatInitPos}) {
    if (chatWindowOverlayEntry != null) return;
    isWindowFocus.value = true;
    _blockableOverlayState.setMiddleBlocked(true);

    final overlayState = _blockableOverlayState.state;
    if (overlayState == null) return;
    if (isMobile &&
        !gFFI.chatModel.currentKey.isOut && // not in remote page
        gFFI.chatModel.latestReceivedKey != null) {
      gFFI.chatModel.changeCurrentKey(gFFI.chatModel.latestReceivedKey!);
      gFFI.chatModel.mobileClearClientUnread(gFFI.chatModel.currentKey.connId);
    }
    final overlay = OverlayEntry(builder: (context) {
      return Listener(
          onPointerDown: (_) {
            if (!isWindowFocus.value) {
              isWindowFocus.value = true;
              _blockableOverlayState.setMiddleBlocked(true);
            }
          },
          child: DraggableChatWindow(
              position: chatInitPos ?? chatWindowPosition,
              width: 250,
              height: 350,
              chatModel: this));
    });
    overlayState.insert(overlay);
    chatWindowOverlayEntry = overlay;
    requestChatInputFocus();
  }

  hideChatWindowOverlay() {
    if (chatWindowOverlayEntry != null) {
      _blockableOverlayState.setMiddleBlocked(false);
      chatWindowOverlayEntry!.remove();
      chatWindowOverlayEntry = null;
      return;
    }
  }

  _isChatOverlayHide() =>
      ((!(isDesktop || isWebDesktop) && chatIconOverlayEntry == null) ||
          chatWindowOverlayEntry == null);

  toggleChatOverlay({Offset? chatInitPos}) {
    if (_isChatOverlayHide()) {
      gFFI.invokeMethod("enable_soft_keyboard", true);
      if (!(isDesktop || isWebDesktop)) {
        showChatIconOverlay();
      }
      showChatWindowOverlay(chatInitPos: chatInitPos);
    } else {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  hideChatOverlay() {
    if (!_isChatOverlayHide()) {
      hideChatIconOverlay();
      hideChatWindowOverlay();
    }
  }

  showChatPage(MessageKey key) async {
    if (isDesktop) {
      if (isConnManager) {
        if (!_isShowCMSidePage) {
          await toggleCMChatPage(key);
        }
      } else {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    } else {
      if (key.connId == clientModeID) {
        if (_isChatOverlayHide()) {
          await toggleChatOverlay();
        }
      }
    }
  }

  toggleCMChatPage(MessageKey key) async {
    if (gFFI.chatModel.currentKey != key) {
      gFFI.chatModel.changeCurrentKey(key);
    }
    await toggleCMSidePage();
  }

  toggleCMFilePage() async {
    await toggleCMSidePage();
  }

  var _togglingCMSidePage = false; // protect order for await
  toggleCMSidePage() async {
    if (_togglingCMSidePage) return false;
    _togglingCMSidePage = true;
    if (_isShowCMSidePage) {
      _isShowCMSidePage = !_isShowCMSidePage;
      notifyListeners();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    } else {
      final currentSelectedTab =
          gFFI.serverModel.tabController.state.value.selectedTabInfo;
      final client = parent.target?.serverModel.clients.firstWhereOrNull(
          (client) => client.id.toString() == currentSelectedTab.key);
      if (client != null) {
        client.unreadChatMessageCount.value = 0;
      }
      requestChatInputFocus();
      await windowManager.show();
      await windowManager.setSizeAlignment(
          kConnectionManagerWindowSizeOpenChat, Alignment.topRight);
      _isShowCMSidePage = !_isShowCMSidePage;
      notifyListeners();
    }
    _togglingCMSidePage = false;
  }

  changeCurrentKey(MessageKey key) {
    updateConnIdOfKey(key);
    String? peerName;
    if (key.connId == clientModeID) {
      peerName = parent.target?.ffiModel.pi.username;
    } else {
      peerName = parent.target?.serverModel.clients
          .firstWhereOrNull((client) => client.peerId == key.peerId)
          ?.name;
    }
    if (!_messages.containsKey(key)) {
      final chatUser = ChatUser(
        id: key.peerId,
        firstName: peerName,
      );
      _messages[key] = MessageBody(chatUser, []);
    } else {
      if (peerName != null && peerName.isNotEmpty) {
        _messages[key]?.chatUser.firstName = peerName;
      }
    }
    _currentKey = key;
    notifyListeners();
    mobileClearClientUnread(key.connId);
  }

  receive(int id, String text) async {
    final session = parent.target;
    if (session == null) {
      debugPrint("Failed to receive msg, session state is null");
      return;
    }
    if (text.isEmpty) return;
    if (appName == 'MiuAI' && isDesktop && text.startsWith(_miuControlPrefix)) {
      await _receiveMiuControl(id, text.substring(_miuControlPrefix.length));
      return;
    }
    if (desktopType == DesktopType.cm && appName != 'MiuAI') {
      await showCmWindow();
    }
    String? peerId;
    if (id == clientModeID) {
      peerId = session.id;
    } else {
      peerId = session.serverModel.clients
          .firstWhereOrNull((e) => e.id == id)
          ?.peerId;
    }
    if (peerId == null) {
      debugPrint("Failed to receive msg, peerId is null");
      return;
    }

    final messagekey = MessageKey(peerId, id);

    // mobile: first message show overlay icon
    if (!isDesktop && chatIconOverlayEntry == null) {
      showChatIconOverlay();
    }
    // show chat page
    if (appName != 'MiuAI') {
      await showChatPage(messagekey);
    }
    late final ChatUser chatUser;
    if (id == clientModeID) {
      chatUser = ChatUser(
        firstName: session.ffiModel.pi.username,
        id: peerId,
      );

      if (isDesktop && appName != 'MiuAI') {
        if (Get.isRegistered<DesktopTabController>()) {
          DesktopTabController tabController = Get.find<DesktopTabController>();
          var index = tabController.state.value.tabs
              .indexWhere((e) => e.key == session.id);
          final notSelected =
              index >= 0 && tabController.state.value.selected != index;
          // minisized: top and switch tab
          // not minisized: add count
          if (await WindowController.fromWindowId(stateGlobal.windowId)
              .isMinimized()) {
            windowOnTop(stateGlobal.windowId);
            if (notSelected) {
              tabController.jumpTo(index);
            }
          } else {
            if (notSelected) {
              UnreadChatCountState.find(peerId).value += 1;
            }
          }
        }
      }
    } else {
      final client = session.serverModel.clients
          .firstWhereOrNull((client) => client.id == id);
      if (client == null) {
        debugPrint("Failed to receive msg, client is null");
        return;
      }
      if (isDesktop) {
        if (appName != 'MiuAI') {
          windowOnTop(null);
          // disable auto jumpTo other tab when hasFocus, and mark unread message
          final currentSelectedTab =
              session.serverModel.tabController.state.value.selectedTabInfo;
          if (currentSelectedTab.key != id.toString() && inputNode.hasFocus) {
            client.unreadChatMessageCount.value += 1;
          } else {
            parent.target?.serverModel.jumpTo(id);
          }
        }
      } else {
        if (HomePage.homeKey.currentState?.isChatPageCurrentTab != true ||
            _currentKey != messagekey) {
          client.unreadChatMessageCount.value += 1;
          mobileUpdateUnreadSum();
        }
      }
      chatUser = ChatUser(id: client.peerId, firstName: client.name);
    }
    insertMessage(messagekey,
        ChatMessage(text: text, user: chatUser, createdAt: DateTime.now()));
    if (appName == 'MiuAI' && isDesktop) {
      _miuUnread[messagekey] = miuUnreadCount(messagekey) + 1;
    }
    if (id == clientModeID || _currentKey.peerId.isEmpty) {
      // client or invalid
      _currentKey = messagekey;
      mobileClearClientUnread(messagekey.connId);
    }
    latestReceivedKey = messagekey;
    notifyListeners();
  }

  Future<void> _receiveMiuControl(int id, String encoded) async {
    if (encoded.length > 4096) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(encoded) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final requestId = data['id'];
    final action = data['action'];
    if (requestId is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(requestId) ||
        action is! String) return;
    final session = parent.target;
    if (session == null || session.closed) return;

    if (id == clientModeID) {
      if (!session.ffiModel.miuPeerAuthenticated || action != 'result') return;
      final pending = _miuPendingControls.remove(requestId);
      if (pending == null) return;
      if (data['visible'] is bool) {
        _miuPetVisible = data['visible'] as bool;
        notifyListeners();
      }
      if (data['aiEnabled'] is bool &&
          data['persona'] is String &&
          data['replyLength'] is int &&
          data['model'] is String &&
          data['thinking'] is String) {
        _miuPetAiEnabled = data['aiEnabled'] as bool;
        _miuPetPersona = data['persona'] as String;
        _miuPetReplyLength = data['replyLength'] as int;
        _miuPetAiModel = data['model'] as String;
        _miuPetAiThinking = data['thinking'] as String;
        notifyListeners();
      }
      pending.complete(data);
      return;
    }

    if (desktopType != DesktopType.cm) return;
    final clients = session.serverModel.clients;
    final client = clients.firstWhereOrNull((client) => client.id == id);
    if (client == null ||
        !client.authorized ||
        client.disconnected ||
        client.isFileTransfer ||
        client.isViewCamera ||
        client.isTerminal ||
        client.portForward.isNotEmpty) return;
    var ok = false;
    if (action == 'pet-state') {
      ok = true;
    } else if (action == 'pet-visible' && data['value'] is bool) {
      session.serverModel.setMiuPetVisible(data['value'] as bool);
      ok = true;
    } else if (action == 'open-image' && data['value'] is String) {
      if (client.keyboard && client.file) {
        ok = await _openMiuImage(data['value'] as String);
      }
    } else if (action == 'ai-state') {
      ok = true;
    } else if (action == 'history-page' && data['value'] is Map) {
      final cursor = data['value'] as Map;
      final before = cursor['before'];
      final offset = cursor['offset'];
      if ((before == null || before is int && before > 0) &&
          offset is int && offset >= 0 && offset <= 4000) ok = true;
    } else if (action == 'ai-settings' && data['value'] is Map) {
      final settings = data['value'] as Map;
      final enabled = settings['enabled'];
      final persona = settings['persona'];
      final replyLength = settings['replyLength'];
      final model = settings['model'];
      final thinking = settings['thinking'];
      if (enabled is bool &&
          persona is String &&
          persona.length <= 1500 &&
          replyLength is int &&
          replyLength >= 1 &&
          replyLength <= 3 &&
          (model == 'deepseek-flash' || model == 'deepseek-v4-pro') &&
          (thinking == 'none' || thinking == 'low' ||
              thinking == 'high' || thinking == 'max')) {
        try {
          if (enabled && MiuAiCredentialStore().read()?.isNotEmpty != true) {
            throw StateError('B 机尚未设置 DeepSeek API Key');
          }
          await bind.mainSetLocalOption(key: 'miu-ai-persona', value: persona);
          await bind.mainSetLocalOption(
              key: 'miu-ai-reply-length', value: replyLength.toString());
          await bind.mainSetLocalOption(key: 'miu-ai-model', value: model);
          await bind.mainSetLocalOption(key: 'miu-ai-thinking', value: thinking);
          await bind.mainSetLocalOption(
              key: 'miu-ai-enabled', value: enabled ? 'Y' : 'N');
          ok = true;
        } catch (_) {
          ok = false;
        }
      }
    } else {
      return;
    }
    if (clients.any((current) =>
        current.id == id && current.authorized && !current.disconnected)) {
      final result = <String, dynamic>{
        'id': requestId,
        'action': 'result',
        'ok': ok,
        'visible': session.serverModel.miuPetVisible,
      };
      if (action == 'ai-state' || action == 'ai-settings') {
        result.addAll(_readMiuPetAiSettings());
      } else if (action == 'history-page' && ok) {
        final cursor = data['value'] as Map;
        result['historyPage'] = MiuAiHistoryStore.instance.page(
          before: cursor['before'] as int?,
          offset: cursor['offset'] as int,
        );
      }
      bind.cmSendChat(
          connId: id,
          msg: '$_miuControlPrefix${jsonEncode(result)}');
    }
  }

  Map<String, dynamic> _readMiuPetAiSettings() {
    final length = int.tryParse(
        bind.mainGetLocalOption(key: 'miu-ai-reply-length'));
    return {
      'aiEnabled': bind.mainGetLocalOption(key: 'miu-ai-enabled') == 'Y' &&
          MiuAiCredentialStore().read()?.isNotEmpty == true,
      'persona': bind.mainGetLocalOption(key: 'miu-ai-persona'),
      'replyLength': length != null && length >= 1 && length <= 3 ? length : 1,
      'model': switch (bind.mainGetLocalOption(key: 'miu-ai-model')) {
        'deepseek-v4-pro' => 'deepseek-v4-pro',
        _ => 'deepseek-flash',
      },
      'thinking': switch (bind.mainGetLocalOption(key: 'miu-ai-thinking')) {
        'low' => 'low',
        'high' => 'high',
        'max' => 'max',
        _ => 'none',
      },
    };
  }

  Future<bool> _openMiuImage(String remotePath) async {
    final home = Platform.environment['USERPROFILE'] ?? '';
    if (!isMiuImageInHome(remotePath, home)) return false;
    final file = File(remotePath);
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) return false;
      final resolved = await file.resolveSymbolicLinks();
      if (!isMiuImageInHome(resolved, home)) return false;
      final size = await file.length();
      if (size < 1 || size > 25 * 1024 * 1024) return false;
      return await launchUrl(Uri.file(file.path),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _requestMiuControl(
      String action, Object? value) async {
    final session = parent.target;
    if (!isWindows ||
        appName != 'MiuAI' ||
        session == null ||
        session.closed ||
        session.connType != ConnType.defaultConn ||
        !session.ffiModel.miuPeerAuthenticated) return null;
    final requestId = const Uuid().v4().replaceAll('-', '');
    final pending = Completer<Map<String, dynamic>>();
    _miuPendingControls[requestId] = pending;
    try {
      final encoded = jsonEncode({
        'id': requestId,
        'action': action,
        'value': value,
      });
      if (encoded.length > 4096) return null;
      bind.sessionSendChat(
          sessionId: sessionId,
          text: '$_miuControlPrefix$encoded');
      return await pending.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    } finally {
      _miuPendingControls.remove(requestId);
    }
  }

  Future<void> refreshMiuPetVisible() async {
    await _requestMiuControl('pet-state', null);
  }

  Future<bool> setMiuPetVisible(bool visible) async {
    final result = await _requestMiuControl('pet-visible', visible);
    return result?['ok'] == true && result?['visible'] == visible;
  }

  Future<bool> requestMiuOpenImage(String remotePath) async {
    if (!_miuImageName.hasMatch(path.windows.basename(remotePath))) return false;
    final result = await _requestMiuControl('open-image', remotePath);
    return result?['ok'] == true;
  }

  Future<void> refreshMiuPetAiSettings() async {
    await _requestMiuControl('ai-state', null);
  }

  Future<void> refreshMiuAiHistory() async {
    final epoch = ++_miuHistoryEpoch;
    _miuAiHistory = [];
    notifyListeners();
    int? before;
    var offset = 0;
    final seen = <String>{};
    final loaded = <MiuAiHistoryEntry>[];
    int? partialId;
    bool? partialFromUser;
    var partialText = '';
    for (var page = 0; page < 160; page++) {
      if (!seen.add('$before:$offset')) return;
      final result = await _requestMiuControl(
          'history-page', {'before': before, 'offset': offset});
      if (epoch != _miuHistoryEpoch) return;
      final session = parent.target;
      if (session == null || session.closed ||
          !session.ffiModel.miuPeerAuthenticated ||
          result?['ok'] != true || result?['historyPage'] is! Map) return;
      final response = result!['historyPage'] as Map;
      final parts = response['entries'];
      if (parts is! List || parts.length > 24 || response['done'] is! bool) return;
      for (final part in parts) {
        if (part is! Map ||
            part['id'] is! int ||
            part['fromUser'] is! bool ||
            part['text'] is! String ||
            part['complete'] is! bool) return;
        final id = part['id'] as int;
        final fromUser = part['fromUser'] as bool;
        final text = part['text'] as String;
        if (id < 1 || text.length > 4000 ||
            (partialId != null && (id != partialId ||
                fromUser != partialFromUser))) return;
        partialId ??= id;
        partialFromUser ??= fromUser;
        partialText += text;
        if (partialText.length > 4000) return;
        if (part['complete'] == true) {
          loaded.add(MiuAiHistoryEntry(id, partialText,
              fromUser: fromUser));
          partialId = null;
          partialFromUser = null;
          partialText = '';
          if (loaded.length > 24) return;
        }
      }
      if (response['done'] == true) {
        if (partialId != null) return;
        _miuAiHistory = loaded;
        notifyListeners();
        return;
      }
      if (response['nextBefore'] is! int ||
          response['nextOffset'] is! int) return;
      before = response['nextBefore'] as int;
      offset = response['nextOffset'] as int;
      if (before < 1 || offset < 0 || offset > 4000) return;
    }
  }

  Future<bool> setMiuPetAiSettings({
    required bool enabled,
    required String persona,
    required int replyLength,
    required String model,
    required String thinking,
  }) async {
    if (persona.length > 1500 || replyLength < 1 || replyLength > 3 ||
        (model != 'deepseek-flash' && model != 'deepseek-v4-pro') ||
        !{'none', 'low', 'high', 'max'}.contains(thinking)) {
      return false;
    }
    final result = await _requestMiuControl('ai-settings', {
      'enabled': enabled,
      'persona': persona,
      'replyLength': replyLength,
      'model': model,
      'thinking': thinking,
    });
    return result?['ok'] == true &&
        result?['aiEnabled'] == enabled &&
        result?['persona'] == persona &&
        result?['replyLength'] == replyLength &&
        result?['model'] == model &&
        result?['thinking'] == thinking;
  }

  void resetMiuControlState() {
    _miuPetVisible = null;
    _miuPetAiEnabled = null;
    _miuPetPersona = null;
    _miuPetReplyLength = null;
    _miuPetAiModel = null;
    _miuPetAiThinking = null;
    _miuAiHistory = [];
    _miuHistoryEpoch++;
    for (final pending in _miuPendingControls.values) {
      if (!pending.isCompleted) pending.complete(<String, dynamic>{'ok': false});
    }
    _miuPendingControls.clear();
    notifyListeners();
  }

  send(ChatMessage message) {
    String trimmedText = message.text.trim();
    if (trimmedText.isEmpty) {
      return;
    }
    message.text = trimmedText;
    insertMessage(_currentKey, message);
    if (_currentKey.connId == clientModeID && parent.target != null) {
      bind.sessionSendChat(sessionId: sessionId, text: message.text);
    } else {
      bind.cmSendChat(connId: _currentKey.connId, msg: message.text);
    }

    notifyListeners();
    inputNode.requestFocus();
  }

  bool sendMiuMessage(MessageKey key, String text) {
    final messageText = text.trim();
    final session = parent.target;
    if (messageText.isEmpty || session == null || session.closed) return false;
    if (key.isOut &&
        (session.id != key.peerId || !session.ffiModel.miuPeerAuthenticated)) {
      return false;
    }
    if (!key.isOut && !session.serverModel.clients.any((client) =>
        client.id == key.connId && client.authorized && !client.disconnected)) {
      return false;
    }
    insertMessage(
      key,
      ChatMessage(text: messageText, user: me, createdAt: DateTime.now()),
    );
    if (key.isOut) {
      bind.sessionSendChat(sessionId: sessionId, text: messageText);
    } else {
      bind.cmSendChat(connId: key.connId, msg: messageText);
    }
    notifyListeners();
    return true;
  }

  insertMessage(MessageKey key, ChatMessage message) {
    updateConnIdOfKey(key);
    if (!_messages.containsKey(key)) {
      _messages[key] = MessageBody(message.user, []);
    }
    _messages[key]?.insert(message);
  }

  updateConnIdOfKey(MessageKey key) {
    if (_messages.keys
            .toList()
            .firstWhereOrNull((e) => e == key && e.connId != key.connId) !=
        null) {
      final value = _messages.remove(key);
      if (value != null) {
        _messages[key] = value;
      }
    }
    if (_currentKey == key || _currentKey.peerId.isEmpty) {
      _currentKey = key; // hash != assign
    }
  }

  void mobileUpdateUnreadSum() {
    if (!isMobile) return;
    var sum = 0;
    parent.target?.serverModel.clients
        .map((e) => sum += e.unreadChatMessageCount.value)
        .toList();
    Future.delayed(Duration.zero, () {
      mobileUnreadSum.value = sum;
    });
  }

  void mobileClearClientUnread(int id) {
    if (!isMobile) return;
    final client = parent.target?.serverModel.clients
        .firstWhereOrNull((client) => client.id == id);
    if (client != null) {
      Future.delayed(Duration.zero, () {
        client.unreadChatMessageCount.value = 0;
        mobileUpdateUnreadSum();
      });
    }
  }

  close() {
    hideChatIconOverlay();
    hideChatWindowOverlay();
    notifyListeners();
  }

  resetClientMode() {
    _messages[clientModeID]?.clear();
  }

  void requestChatInputFocus() {
    Timer(Duration(milliseconds: 100), () {
      if (inputNode.hasListeners && inputNode.canRequestFocus) {
        inputNode.requestFocus();
      }
    });
  }

  void onVoiceCallWaiting() {
    _voiceCallStatus.value = VoiceCallStatus.waitingForResponse;
  }

  void onVoiceCallStarted() {
    _voiceCallStatus.value = VoiceCallStatus.connected;
    if (isAndroid) {
      parent.target?.invokeMethod("on_voice_call_started");
    }
  }

  void onVoiceCallClosed(String reason) {
    _voiceCallStatus.value = VoiceCallStatus.notStarted;
    if (isAndroid) {
      // We can always invoke "on_voice_call_closed"
      // no matter if the `_voiceCallStatus` was `VoiceCallStatus.notStarted` or not.
      parent.target?.invokeMethod("on_voice_call_closed");
    }
  }

  void onVoiceCallIncoming() {
    if (isConnManager) {
      _voiceCallStatus.value = VoiceCallStatus.incoming;
    }
  }

  void closeVoiceCall() {
    bind.sessionCloseVoiceCall(sessionId: sessionId);
  }
}

enum VoiceCallStatus {
  notStarted,
  waitingForResponse,
  connected,
  // Connection manager only.
  incoming
}
