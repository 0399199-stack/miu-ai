import 'dart:async';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_notice.dart';
import 'package:flutter_hbb/desktop/widgets/miu_notice_composer.dart';

void main() {
  Future<void> open(
      WidgetTester tester, Future<bool> Function(MiuNotice) onSend) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => MiuNoticeComposer(onSend: onSend)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sends entered values once and waits for B acknowledgement',
      (tester) async {
    final reply = Completer<bool>();
    final sent = <MiuNotice>[];
    await open(tester, (notice) {
      sent.add(notice);
      return reply.future;
    });
    await tester.enterText(
        find.byKey(const ValueKey('miu-notice-title')), '喝水提醒');
    await tester.enterText(
        find.byKey(const ValueKey('miu-notice-text')), '休息一下\n记得喝水');
    await tester.enterText(
        find.byKey(const ValueKey('miu-notice-seconds')), '30');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '红色'));
    await tester.tap(find.widgetWithText(ChoiceChip, '红色'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('miu-notice-send')));
    await tester.tap(find.byKey(const ValueKey('miu-notice-send')));
    await tester.tap(find.byKey(const ValueKey('miu-notice-send')));
    await tester.pump();
    expect(sent, hasLength(1));
    expect(sent.single.title, '喝水提醒');
    expect(sent.single.text, '休息一下\n记得喝水');
    expect(sent.single.seconds, 30);
    expect(sent.single.sound, isTrue);
    expect(sent.single.textColor, '#C52B40');
    expect(find.text('B 机已显示通知'), findsNothing);
    reply.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('B 机已显示通知'), findsOneWidget);
  });

  testWidgets(
      'failure preserves input without reporting success, close dismisses',
      (tester) async {
    tester.view.physicalSize = const Size(420, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await open(tester, (_) async {
      calls++;
      return false;
    });
    await tester.enterText(
        find.byKey(const ValueKey('miu-notice-text')), '稍后再试');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('miu-notice-send')));
    await tester.tap(find.byKey(const ValueKey('miu-notice-send')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('B 机已显示通知'), findsNothing);
    expect(find.text('发送失败，请检查连接及 B 机版本后重试'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('miu-notice-text')))
            .controller!
            .text,
        '稍后再试');
    await tester.ensureVisible(find.byTooltip('关闭'));
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuNoticeComposer), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom color cancels or confirms without sending a notice',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <MiuNotice>[];
    await open(tester, (notice) async {
      sent.add(notice);
      return true;
    });
    await tester.enterText(
        find.byKey(const ValueKey('miu-notice-text')), '自定义颜色通知');
    await tester.pumpAndSettle();
    for (final confirm in [false, true]) {
      await tester.ensureVisible(find.text('自定义颜色'));
      await tester.tap(find.text('自定义颜色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wheel'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(ColorPicker), matching: find.byType(TextField)),
          'A91238');
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm ? 'OK' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsNothing);
      expect(sent, isEmpty);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('miu-notice-color-preview')))
              .style!
              .color,
          confirm ? const Color(0xFFA91238) : const Color(0xFF1C2740));
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('miu-notice-send')));
    await tester.tap(find.byKey(const ValueKey('miu-notice-send')));
    await tester.pumpAndSettle();
    expect(sent.single.textColor, '#A91238');
  });
}
