// main window right pane

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Dialog;
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/miu_glass.dart';
import 'package:flutter_hbb/desktop/widgets/miu_home_device.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/dialog.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://rustdesk.com/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
            // ready && public
            // No need to show the guide if is custom client.
            if (!isIncomingOnly && !bind.isCustomClient()) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  bool get _miuController =>
      isWindows && appName == 'MiuAI' && !isMiuHostOnly;

  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;
  bool _miuDeviceGrid = true;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  @override
  void initState() {
    super.initState();
    if (_miuController) bind.mainLoadRecentPeers();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
            if (_miuController) _idEditingController.text = formatID(lastRemoteId);
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_miuController) return _buildMiuController(context);
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Column(
      children: [
        Expanded(
            child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: _buildRemoteIDTextField(context),
            ).paddingOnly(top: 28, bottom: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(translate('Recent devices'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ).paddingOnly(bottom: 12),
            Expanded(
              child: MiuGlass(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 4),
                child: PeerTabPage(),
              ),
            ),
          ],
        ).paddingOnly(left: 24, right: 24, bottom: 12)),
        if (!isOutgoingOnly) OnlineStatusWidget()
      ],
    );
  }

  Widget _buildMiuController(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFFA9BFD9) : const Color(0xFF6882A6);
    final canConnect = _idController.id.trim().isNotEmpty;
    final buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(13));
    Widget connectButton({bool viewOnly = false}) => SizedBox(
          height: 46,
          width: 108,
          child: viewOnly
              ? OutlinedButton(
                  onPressed:
                      canConnect ? () => onConnect(viewOnly: true) : null,
                  style: OutlinedButton.styleFrom(
                      shape: buttonShape,
                      side: BorderSide(
                          color: const Color(0xFF9BC5FF).withOpacity(0.5))),
                  child: Text(translate('View only')))
              : FilledButton(
                  onPressed: canConnect ? () => onConnect() : null,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2678FF),
                      foregroundColor: Colors.white,
                      shape: buttonShape),
                  child: Text(translate('Connect'))),
        );
    final input = TextField(
      controller: _idEditingController,
      focusNode: _idFocusNode,
      inputFormatters: [IDTextInputFormatter()],
      onChanged: (value) => setState(() => _idController.id = value),
      onSubmitted: (_) => onConnect(),
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.desktop_windows_outlined, size: 21),
        suffixIcon: canConnect
            ? IconButton(
                tooltip: translate('Clear'),
                icon: const Icon(Icons.cancel_rounded, size: 17),
                onPressed: () => setState(() {
                      _idController.id = '';
                      _idEditingController.clear();
                      _idFocusNode.requestFocus();
                    }))
            : null,
        hintText: translate('Enter Remote ID'),
        hintStyle: TextStyle(color: muted, fontSize: 14),
        filled: true,
        fillColor: Colors.white.withOpacity(dark ? 0.05 : 0.68),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                BorderSide(color: const Color(0xFF91BDFC).withOpacity(0.22))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide:
                BorderSide(color: const Color(0xFF91BDFC).withOpacity(0.22))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFF569BFF), width: 1.5)),
      ),
    );
    final pairing = TextButton.icon(
        onPressed: _showMiuControllerKey,
        icon: const Icon(Icons.key_rounded, size: 17),
        label: const Text('首次配对密钥'));

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('我的设备',
                        style: TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text('连接、协作与任务',
                        style: TextStyle(color: muted, fontSize: 14)),
                  ])),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(dark ? 0.06 : 0.55),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.hub_outlined, size: 15, color: muted),
                    const SizedBox(width: 7),
                    Text('A 控制端', style: TextStyle(fontSize: 12, color: muted)),
                  ])),
            ]),
            const SizedBox(height: 20),
            MiuGlass(
                radius: 22,
                padding: const EdgeInsets.all(13),
                child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 810;
                  return Column(children: [
                    if (constraints.maxWidth >= 580)
                      Row(children: [
                        Expanded(child: input),
                        const SizedBox(width: 10),
                        connectButton(),
                        const SizedBox(width: 8),
                        connectButton(viewOnly: true),
                        if (wide) ...[const SizedBox(width: 8), pairing]
                      ])
                    else ...[
                      input,
                      const SizedBox(height: 10),
                      Row(children: [
                        connectButton(),
                        const SizedBox(width: 8),
                        connectButton(viewOnly: true)
                      ])
                    ],
                    if (!wide)
                      Align(alignment: Alignment.centerRight, child: pairing),
                  ]);
                })),
            const SizedBox(height: 22),
            AnimatedBuilder(
                animation: gFFI.recentPeersModel,
                builder: (context, _) {
                  final peers = gFFI.recentPeersModel.peers;
                  return MiuGlass(
                      radius: 24,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text('我的设备（${peers.length}）',
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700))),
                              IconButton(
                                  tooltip: '卡片视图',
                                  onPressed: () =>
                                      setState(() => _miuDeviceGrid = true),
                                  icon: Icon(Icons.grid_view_rounded,
                                      size: 19,
                                      color: _miuDeviceGrid
                                          ? const Color(0xFF2678FF)
                                          : muted)),
                              IconButton(
                                  tooltip: '列表视图',
                                  onPressed: () =>
                                      setState(() => _miuDeviceGrid = false),
                                  icon: Icon(Icons.view_agenda_outlined,
                                      size: 19,
                                      color: !_miuDeviceGrid
                                          ? const Color(0xFF2678FF)
                                          : muted)),
                            ]),
                            const SizedBox(height: 12),
                            if (peers.isEmpty)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Column(children: [
                                    const Icon(Icons.devices_rounded,
                                        size: 44, color: Color(0xFF77AAE8)),
                                    const SizedBox(height: 12),
                                    Text(translate('No recent devices'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 5),
                                    Text('在上方输入 B 机设备 ID，开始第一次连接',
                                        style: TextStyle(
                                            color: muted, fontSize: 12)),
                                  ]))
                            else
                              LayoutBuilder(builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 930
                                    ? 3
                                    : constraints.maxWidth >= 580
                                        ? 2
                                        : 1;
                                final compact = !_miuDeviceGrid &&
                                    constraints.maxWidth >= 580;
                                final width = compact
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth -
                                            14 * (columns - 1)) /
                                        columns;
                                return AnimatedSize(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : const Duration(milliseconds: 220),
                                  alignment: Alignment.topCenter,
                                  curve: Curves.easeOutCubic,
                                  child: Wrap(
                                    spacing: 14,
                                    runSpacing: 14,
                                    children: peers
                                        .map((peer) => SizedBox(
                                            width: width,
                                            child: MiuHomeDevice(
                                              key: ValueKey(peer.id),
                                              name: peer.alias.isNotEmpty
                                                  ? peer.alias
                                                  : peer.hostname.isNotEmpty
                                                      ? peer.hostname
                                                      : peer.id,
                                              id: formatID(peer.id),
                                              details: [
                                                peer.platform,
                                                if (peer.alias.isNotEmpty)
                                                  peer.hostname
                                              ]
                                                  .where(
                                                      (part) => part.isNotEmpty)
                                                  .join(' · '),
                                              compact: compact,
                                              onConnect: () =>
                                                  connect(context, peer.id),
                                              onView: () => connect(
                                                  context, peer.id,
                                                  viewOnly: true),
                                              onRename: () =>
                                                  _renameMiuPeer(peer),
                                              menu: _miuPeerMenu(peer),
                                            )))
                                        .toList(),
                                  ),
                                );
                              }),
                          ]));
                }),
            const SizedBox(height: 18),
            MiuGlass(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('快捷操作',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                          canConnect
                              ? '目标设备 · ${formatID(_idController.id)}'
                              : '输入设备 ID 后使用远程功能',
                          style: TextStyle(color: muted, fontSize: 12)),
                      const SizedBox(height: 14),
                      LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 700 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - 10 * (columns - 1)) /
                                columns;
                        Widget action(String label, String subtitle,
                                IconData icon, VoidCallback? onTap) =>
                            SizedBox(
                                width: width,
                                child: MiuHoverSurface(
                                    radius: 16,
                                    onTap: onTap,
                                    child: Opacity(
                                        opacity: onTap == null ? 0.45 : 1,
                                        child: Row(children: [
                                          Icon(icon,
                                              color: const Color(0xFF2678FF),
                                              size: 24),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(label,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const SizedBox(height: 3),
                                                Text(subtitle,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: muted)),
                                              ])),
                                        ]))));
                        return Wrap(spacing: 10, runSpacing: 10, children: [
                          action(
                              translate('Transfer file'),
                              '发送与接收文件',
                              Icons.folder_outlined,
                              canConnect
                                  ? () => onConnect(isFileTransfer: true)
                                  : null),
                          action(
                              translate('Terminal'),
                              '远程命令行',
                              Icons.terminal_rounded,
                              canConnect
                                  ? () => onConnect(isTerminal: true)
                                  : null),
                          action(
                              translate('Quick tasks'),
                              '连接后打开任务中心',
                              Icons.bolt_rounded,
                              canConnect
                                  ? () {
                                      onConnect();
                                      showToast(translate(
                                          'Open quick tasks from the remote toolbar'));
                                    }
                                  : null),
                          if (!bind.isDisableSettings())
                            action(
                                translate('Settings'),
                                '连接与应用偏好',
                                Icons.tune_rounded,
                                DesktopTabPage.onAddSetting),
                        ]);
                      }),
                    ])),
          ]),
        ),
      ),
    );
  }

  void _renameMiuPeer(Peer peer) {
    renameDialog(
        oldName: peer.alias,
        onSubmit: (alias) async {
          if (alias == peer.alias) return;
          await bind.mainSetPeerAlias(id: peer.id, alias: alias);
          bind.mainLoadRecentPeers();
        });
  }

  Widget _miuPeerMenu(Peer peer) => PopupMenuButton<String>(
        tooltip: translate('More'),
        icon: const Icon(Icons.more_horiz_rounded, size: 21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF203149)
            : const Color(0xFFF5FAFF),
        elevation: 8,
        onSelected: (value) {
          if (value == 'rename') {
            _renameMiuPeer(peer);
          } else if (value == 'delete') {
            deleteConfirmDialog(() async {
              await bind.mainRemovePeer(id: peer.id);
              bind.mainLoadRecentPeers();
            }, '从 A 机删除 ${peer.getId()}？将清除本机保存的密码和偏好，不影响 B 机配对。');
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('设置备注')),
          PopupMenuItem(value: 'delete', child: Text('删除记录')),
        ],
      );
  Future<void> _showMiuControllerKey() async {
    var key = await bind.mainGetCommon(key: 'miu-controller-public-key');
    if (key.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 300));
      key = await bind.mainGetCommon(key: 'miu-controller-public-key');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => material.Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: MiuGlass(
            radius: 30,
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('A 机主控密钥',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('在 B 机的首次配对页面粘贴此密钥，并在 B 机设置长期密码。',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                SelectableText(key.isEmpty ? '密钥准备中，请稍后重新打开' : key,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 22),
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: key.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: key));
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            showToast('主控密钥已复制');
                          },
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('复制密钥'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool viewOnly = false,
      bool isViewCamera = false,
      bool isTerminal = false,
      bool isTcpTunneling = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        viewOnly: viewOnly,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling);
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    var w = MiuGlass(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(translate('Connect a device'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(translate('Enter device ID, then choose an action'),
                  style: Theme.of(context).textTheme.bodySmall),
            ).paddingOnly(top: 5, bottom: 18),
            Row(
              children: [
                Expanded(
                    child: RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                      _allPeersLoader.queryOnlines(_autocompleteOpts);
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    return Obx(() => TextField(
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          focusNode: fieldFocusNode,
                          style: const TextStyle(
                            fontFamily: 'WorkSans',
                            fontSize: 22,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          cursorColor:
                              Theme.of(context).textTheme.titleLarge?.color,
                          decoration: InputDecoration(
                              filled: false,
                              counterText: '',
                              hintText: _idInputFocused.value
                                  ? null
                                  : translate('Enter Remote ID'),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 13)),
                          controller: fieldTextEditingController,
                          inputFormatters: [IDTextInputFormatter()],
                          onChanged: (v) {
                            _idController.id = v;
                          },
                          onSubmitted: (_) {
                            onConnect();
                          },
                        ).workaroundFreezeLinuxMint());
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: 319,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
                )),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              Widget action(String label, IconData icon, VoidCallback onPressed,
                  {bool primary = false}) {
                return SizedBox(
                  width: width,
                  height: 46,
                  child: primary
                      ? ElevatedButton.icon(
                          onPressed: onPressed,
                          icon: Icon(icon, size: 18),
                          label: Text(label),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: const Color(0xFF647FE8),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: onPressed,
                          icon: Icon(icon, size: 18),
                          label: Text(label),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                );
              }

              return Wrap(spacing: 10, runSpacing: 10, children: [
                action(translate('Connect'), Icons.desktop_windows_outlined,
                    () => onConnect(), primary: true),
                action(translate('View only'), Icons.visibility_outlined,
                    () => onConnect(viewOnly: true)),
                action(translate('Transfer file'), Icons.folder_copy_outlined,
                    () => onConnect(isFileTransfer: true)),
                action(translate('Terminal'), Icons.terminal_outlined,
                    () => onConnect(isTerminal: true)),
              ]);
            }),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: translate('More'),
                onSelected: (value) {
                  if (value == 'camera') onConnect(isViewCamera: true);
                  if (value == 'tunnel') onConnect(isTcpTunneling: true);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'camera', child: Text(translate('View camera'))),
                  if (isDesktop)
                    PopupMenuItem(
                        value: 'tunnel',
                        child: Text(translate('TCP tunneling'))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.more_horiz_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(translate('More')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
    return Container(
        constraints: const BoxConstraints(maxWidth: 600), child: w);
  }
}
