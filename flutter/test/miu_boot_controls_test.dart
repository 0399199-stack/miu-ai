import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_boot_controls.dart';
import 'package:flutter_hbb/desktop/widgets/miu_boot_player.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';

class _Chat extends ChangeNotifier implements ChatModel {
  @override
  MiuBootSettings? miuBootSettings = const MiuBootSettings();
  @override
  bool? miuBootAvailable = true;
  int plays = 0;
  bool refreshSucceeds = true;
  @override
  Future<bool> refreshMiuBootSettings() async => refreshSucceeds;
  @override
  Future<bool> setMiuBootSettings(MiuBootSettings settings) async {
    miuBootSettings = settings;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> playMiuBoot() async {
    plays++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Peer extends ChangeNotifier implements FfiModel {
  @override
  bool get miuPeerAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Session implements FFI {
  _Session(this.chatModel, this.ffiModel);
  @override
  final _Chat chatModel;
  @override
  final _Peer ffiModel;
  @override
  bool get closed => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Future<_Chat> mount(WidgetTester tester, {bool supported = true}) async {
    final chat = _Chat();
    final peer = _Peer();
    if (!supported) {
      chat.miuBootSettings = null;
      chat.miuBootAvailable = null;
    }
    addTearDown(chat.dispose);
    addTearDown(peer.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 300,
                    child: MiuBootControls(ffi: _Session(chat, peer)))))));
    return chat;
  }

  testWidgets(
      'A saves vivid red, preserves color when toggling login, and plays',
      (tester) async {
    final chat = await mount(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(6));
    await tester.tap(find.widgetWithText(ChoiceChip, '大红'));
    await tester.pumpAndSettle();
    expect(chat.miuBootSettings?.color, '#FF0000');
    expect(find.text('自定义颜色  #FF0000'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(chat.miuBootSettings?.autoPlay, isFalse);
    expect(chat.miuBootSettings?.color, '#FF0000');
    await tester.ensureVisible(find.text('立即在 B 播放'));
    await tester.tap(find.text('立即在 B 播放'));
    await tester.pumpAndSettle();
    expect(chat.plays, 1);
    expect(find.text('B 机已开始播放，可按 Esc 跳过'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed refresh does not report cached settings as freshly read',
      (tester) async {
    final chat = await mount(tester);
    chat.refreshSucceeds = false;
    await tester.tap(find.byTooltip('读取 B 机设置'));
    await tester.pumpAndSettle();
    expect(find.text('已读取 B 机设置'), findsNothing);
    expect(find.text('未收到新设置，请检查连接或升级 B 机'), findsOneWidget);
    expect(chat.miuBootSettings?.color, '#48AAFF');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('older B keeps unsupported controls disabled', (tester) async {
    final chat = await mount(tester, supported: false);
    expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).onSelected,
        isNull);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    await tester.ensureVisible(find.text('立即在 B 播放'));
    await tester.tap(find.text('立即在 B 播放'));
    await tester.pumpAndSettle();
    expect(chat.plays, 0);
    expect(find.text('等待 B 机读取设置；旧版 B 需升级后使用'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
