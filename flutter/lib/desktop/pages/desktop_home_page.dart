import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Dialog;
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/miu_glass.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  bool _miuHostReady = false;
  int _miuHostSessions = 0;
  bool _miuPairingChecked = false;
  bool _miuPairingRefreshing = false;
  String _miuTrustedControllerKey = '';

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (isWindows && appName == 'MiuAI') {
      return _buildBlock(
        child: MiuBackdrop(
          child: isMiuHostOnly
              ? _buildMiuHost(context)
              : const ConnectionPage(),
        ),
      );
    }
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
      child: MiuBackdrop(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildLeftPane(context),
            if (!isIncomingOnly) const SizedBox(width: 8),
            if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                colors: [Color(0xFF6B8AF3), Color(0xFF9F87E8)],
              ),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 21, color: Colors.white),
          ),
          const SizedBox(width: 11),
          const Text('Miu AI',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        ],
      ).paddingOnly(left: 20, right: 16, top: 22, bottom: 18),
      buildTip(context),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: 292.0,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.035)
              : Colors.white.withOpacity(0.28),
          border: Border(
            right: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return const ConnectionPage();
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: MiuGlass(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(translate('ID'),
                    style: Theme.of(context).textTheme.bodySmall),
                buildPopupMenu(context),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: model.serverId,
                    readOnly: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w600),
                  ).workaroundFreezeLinuxMint(),
                ),
                IconButton(
                  tooltip: translate('Copy'),
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: model.serverId.text));
                    showToast(translate('Copied'));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiuHost(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paired = _miuTrustedControllerKey.isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: MiuGlass(
            padding: const EdgeInsets.all(22),
            radius: 30,
            child: ChangeNotifierProvider.value(
              value: gFFI.serverModel,
              child: Consumer<ServerModel>(builder: (context, model, _) {
                final ready = _miuHostReady && !svcStopped.value;
                final status = !_miuPairingChecked
                    ? '正在检查配对状态'
                    : !paired
                        ? '等待首次配对'
                        : _miuHostSessions > 0
                    ? translate('In use ({})')
                        .replaceFirst('{}', '$_miuHostSessions')
                    : ready
                        ? translate('Ready for connections')
                        : translate('Connection service unavailable');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      loadIcon(40),
                      const SizedBox(width: 10),
                      const Text('Miu AI',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(translate('Host only'),
                          style: TextStyle(
                              fontSize: 12,
                              color: dark ? Colors.white70 : const Color(0xFF6680B7))),
                    ]),
                    const SizedBox(height: 23),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: (ready && paired ? const Color(0xFF38BA89) : const Color(0xFFE59A4D))
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle,
                              size: 9,
                              color: ready && paired ? const Color(0xFF38BA89) : const Color(0xFFE59A4D)),
                          const SizedBox(width: 8),
                          Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    MiuGlass(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      radius: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(translate('This device ID'),
                              style: Theme.of(context).textTheme.bodySmall),
                          Row(children: [
                            Expanded(
                              child: Text(model.serverId.text.isEmpty
                                  ? '—'
                                  : model.serverId.text,
                                  style: const TextStyle(
                                      fontSize: 25, fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2)),
                            ),
                            IconButton(
                              tooltip: translate('Copy'),
                              icon: const Icon(Icons.copy_rounded, size: 19),
                              onPressed: model.serverId.text.isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(
                                          ClipboardData(text: model.serverId.text));
                                      showToast(translate('Copied'));
                                    },
                            ),
                          ]),
                          Row(children: [
                            const Icon(Icons.verified_user_outlined,
                                size: 16, color: Color(0xFF5387D9)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(paired ? '已绑定主控设备' : '首次配对后才能连接')),
                            TextButton(
                              onPressed: paired
                                  ? () => DesktopTabPage.onAddSetting(
                                      initialPage: SettingsTabKey.safety)
                                  : _showMiuPairingDialog,
                              child: Text(paired ? translate('Security settings') : '开始配对'),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: paired ? () => windowManager.hide() : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        backgroundColor: const Color(0xFF4D7DF1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                      ),
                      child: Text(paired ? translate('Finish and run in background') : '请先完成配对'),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(translate('Runs in system tray'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshMiuPairing() async {
    if (!isWindows || appName != 'MiuAI' || !isMiuHostOnly ||
        _miuPairingRefreshing) return;
    _miuPairingRefreshing = true;
    try {
      if (await bind.mainGetCommon(key: 'miu-active-connections') == '') return;
      final key = await bind.mainGetCommon(key: 'miu-trusted-controller-pk-service');
      final approveMode = await bind.mainGetCommon(key: 'miu-approve-mode-service');
      final verificationMethod =
          await bind.mainGetCommon(key: 'miu-verification-method-service');
      final passwordSet =
          (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
      bool validKey = false;
      try {
        validKey = RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(key) &&
            base64Decode(key).length == 32;
      } on FormatException {
        validKey = false;
      }
      if (!mounted) return;
      setState(() {
        _miuTrustedControllerKey =
            validKey && passwordSet && approveMode == 'password' &&
                    verificationMethod == kUsePermanentPassword
                ? key
                : '';
        _miuPairingChecked = true;
      });
    } finally {
      _miuPairingRefreshing = false;
    }
  }

  Future<void> _showMiuPairingDialog() async {
    final initialConnections =
        await bind.mainGetCommon(key: 'miu-active-connections');
    if (initialConnections != '0') {
      showToast('请确认连接服务可用，并断开所有远程会话后再配对');
      return;
    }
    final hasPassword =
        (await bind.mainGetCommon(key: 'permanent-password-set')) == 'true';
    if (!mounted) return;
    final keyController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String error = '';
    bool saving = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) => material.Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: MiuGlass(
              radius: 30,
              padding: const EdgeInsets.all(26),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('首次配对',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('在 A 机复制主控密钥，粘贴到这里。完成后只有持有对应私钥的 A 机可连接，连接时仍需长期密码。',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text('完成配对将允许该 A 机无人逐次确认地远控、传输文件和执行命令。',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    TextField(
                      controller: keyController,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'A 机主控密钥',
                        hintText: '粘贴 44 位公钥',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!hasPassword) ...[
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: '设置长期密码（至少 12 位）',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: '再次输入长期密码',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ] else
                      const Text('将沿用此电脑已设置的长期密码。'),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(error, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 22),
                    Row(children: [
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        child: const Text('取消'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final key = keyController.text.trim();
                                bool validKey = false;
                                try {
                                  validKey = RegExp(r'^[A-Za-z0-9+/]{43}=$')
                                          .hasMatch(key) &&
                                      base64Decode(key).length == 32;
                                } on FormatException {
                                  validKey = false;
                                }
                                if (!validKey) {
                                  updateDialog(() => error = '主控密钥格式不正确');
                                  return;
                                }
                                if (!hasPassword &&
                                    (passwordController.text.length < 12 ||
                                        passwordController.text !=
                                            confirmController.text)) {
                                  updateDialog(() => error = '请输入两次相同的长期密码，至少 12 位');
                                  return;
                                }
                                updateDialog(() {
                                  saving = true;
                                  error = '';
                                });
                                final connections = await bind.mainGetCommon(
                                    key: 'miu-active-connections');
                                if (connections != '0') {
                                  updateDialog(() {
                                    saving = false;
                                    error = '请先断开所有远程会话再保存';
                                  });
                                  return;
                                }
                                if (!hasPassword) {
                                  final ok = await bind.mainSetPermanentPasswordWithResult(
                                      password: passwordController.text);
                                  if (!ok) {
                                    updateDialog(() {
                                      saving = false;
                                      error = '长期密码保存失败';
                                    });
                                    return;
                                  }
                                }
                                await bind.mainSetOption(
                                    key: kOptionApproveMode, value: 'password');
                                await bind.mainSetOption(
                                    key: kOptionVerificationMethod,
                                    value: kUsePermanentPassword);
                                await bind.mainSetOption(
                                    key: kOptionEnableKeyboard, value: 'Y');
                                await bind.mainSetOption(
                                    key: kOptionEnableFileTransfer, value: 'Y');
                                await bind.mainSetOption(
                                    key: kOptionEnableTerminal, value: 'Y');
                                await bind.mainSetOption(
                                    key: 'miu-trusted-controller-pk', value: key);
                                var stored = '';
                                var approveMode = '';
                                var verificationMethod = '';
                                for (var attempt = 0; attempt < 3; attempt++) {
                                  stored = await bind.mainGetCommon(
                                      key: 'miu-trusted-controller-pk-service');
                                  approveMode = await bind.mainGetCommon(
                                      key: 'miu-approve-mode-service');
                                  verificationMethod = await bind.mainGetCommon(
                                      key: 'miu-verification-method-service');
                                  if (stored == key &&
                                      approveMode == 'password' &&
                                      verificationMethod ==
                                          kUsePermanentPassword) break;
                                  await Future.delayed(const Duration(milliseconds: 250));
                                }
                                if (stored != key ||
                                    approveMode != 'password' ||
                                    verificationMethod !=
                                        kUsePermanentPassword) {
                                  updateDialog(() {
                                    saving = false;
                                    error = '服务尚未确认配对或长期密码模式，请稍后重试';
                                  });
                                  return;
                                }
                                await _refreshMiuPairing();
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              },
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text(saving ? '保存中…' : '完成配对'),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    keyController.dispose();
    passwordController.dispose();
    confirmController.dispose();
  }

  Widget buildPopupMenu(BuildContext context) {
    return IconButton(
      tooltip: translate('Settings'),
      icon: const Icon(Icons.settings_outlined, size: 17),
      onPressed: DesktopTabPage.onAddSetting,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: MiuGlass(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AutoSizeText(
              translate('One-time Password'),
              style: TextStyle(fontSize: 12, color: textColor?.withOpacity(0.6)),
              maxLines: 1,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: model.serverPasswd,
                    readOnly: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w500),
                  ).workaroundFreezeLinuxMint(),
                ),
                if (showOneTime)
                  IconButton(
                    tooltip: translate('Refresh Password'),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    onPressed: () => bind.mainUpdateTemporaryPassword(),
                  ),
                if (!bind.isDisableSettings())
                  IconButton(
                    tooltip: translate('Change Password'),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    onPressed: () => DesktopSettingPage.switch2page(
                        SettingsTabKey.safety),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isOutgoingOnly)
            Text(translate('Your Desktop'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (!isOutgoingOnly)
            Text(
              translate('desk_tip'),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          if (isOutgoingOnly)
            Text(
              translate('outgoing_only_desk_tip'),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, marginTop, 16, bind.isIncomingOnly() ? marginTop : 0),
      child: Stack(
        children: [
          MiuGlass(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(translate(title),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                if (content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Text(translate(content),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(height: 1.5)),
                  ),
                if (btnText.isNotEmpty)
                  ElevatedButton(
                    onPressed: onPressed,
                    child: Text(translate(btnText)),
                  ),
                if (help != null)
                  TextButton(
                    onPressed: () async => await launchUrl(Uri.parse(link!)),
                    child: Text(translate(help)),
                  ),
              ],
            ),
          ),
          if (closeButton == true)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 17),
                onPressed: closeCard,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshMiuPairing();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      if (isMiuHostOnly) {
        if (!_miuPairingChecked) await _refreshMiuPairing();
        try {
          final status = jsonDecode(await bind.mainGetConnectStatus())
              as Map<String, dynamic>;
          final ready = status['status_num'] == 1;
          final sessions = status['video_conn_count'] as int? ?? 0;
          if (ready != _miuHostReady || sessions != _miuHostSessions) {
            _miuHostReady = ready;
            _miuHostSessions = sessions;
            if (mounted) setState(() {});
          }
        } catch (_) {}
      }
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          viewOnly: call.arguments['viewOnly'] == true,
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
