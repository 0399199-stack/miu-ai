import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/widgets/miu_controller_header.dart';
import 'package:flutter_hbb/mobile/widgets/miu_remote_controls.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/desktop/widgets/miu_notice_composer.dart';

class _WaitingChat extends ChangeNotifier implements ChatModel {
  @override
  Future<bool> refreshMiuBootSettings() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WaitingPeer extends ChangeNotifier implements FfiModel {
  @override
  bool get miuPeerAuthenticated => false;
  @override
  int get miuOverlayIntensity => 100;
  @override
  int get miuOverlayPeriodMs => 1600;
  @override
  String get miuOverlayColor => '#317CFF';
  @override
  String get miuOverlayMode => 'session';
  @override
  String get miuOverlayEffect => 'breathing';
  @override
  bool get miuOverlayModeSupported => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WaitingSession implements FFI {
  @override
  final chatModel = _WaitingChat();
  @override
  final ffiModel = _WaitingPeer();
  @override
  bool get closed => false;
  @override
  String get id => '123456789';
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('mobile controller exposes pairing on a narrow screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var paired = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: MiuControllerHeader(onPair: () => paired = true)))));
    expect(find.text('Miu AI'), findsOneWidget);
    await tester.tap(find.text('首次配对密钥'));
    expect(paired, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile connection introduction remains readable in landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: MiuControllerHeader(onPair: () {})))));
    expect(find.text('你的电脑，随手掌控'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile controls wait for authentication and fit a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _WaitingSession();
    addTearDown(session.chatModel.dispose);
    addTearDown(session.ffiModel.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MiuMobileControls(ffi: session))));
    await tester.tap(find.text('桌面宠物'));
    await tester.pumpAndSettle();
    for (final toggle in tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))) {
      expect(toggle.onChanged, isNull);
    }
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, '发送置顶通知')).enabled, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expanded glow and boot controls scroll on a narrow phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _WaitingSession();
    addTearDown(session.chatModel.dispose);
    addTearDown(session.ffiModel.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MiuMobileControls(ffi: session))));
    await tester.tap(find.text('屏幕光效与开机动画'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('立即在 B 播放'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('notice editor fits a narrow phone with keyboard space reserved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), viewInsets: EdgeInsets.only(bottom: 240)),
      child: Scaffold(body: MiuNoticeComposer(onSend: (_) async => true)))));
    await tester.enterText(find.byKey(const ValueKey('miu-notice-text')), '手机通知');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('miu-notice-send')));
    await tester.tap(find.byKey(const ValueKey('miu-notice-send')));
    await tester.pumpAndSettle();
    expect(find.text('B 机已显示通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
