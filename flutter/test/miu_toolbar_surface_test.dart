import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_glass.dart';
import 'package:flutter_hbb/desktop/widgets/miu_toolbar_surface.dart';

Widget _menu(String label, {bool long = false, VoidCallback? onDismiss}) =>
    MiuToolbarMenu(
      icon: label == '宠物' ? Icons.pets_rounded : Icons.palette_outlined,
      label: label,
      onDismiss: onDismiss,
      builder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MiuPanelHeading('$label 设置', onClose: close),
          for (var i = 0; i < (long ? 18 : 1); i++)
            MiuPanelAction(
              icon: Icons.check_rounded,
              label: '$label 选项 $i',
              onPressed: () {},
            ),
        ],
      ),
    );

MiuToolbarChip _chip(WidgetTester tester, String label) => tester
    .widgetList<MiuToolbarChip>(find.byType(MiuToolbarChip))
    .singleWhere((chip) => chip.label == label);

void main() {
  testWidgets(
      'glass menu opens, shows selection, closes and consumes outside tap',
      (tester) async {
    var remoteTaps = 0;
    var dismissals = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
          body: Stack(children: [
        Positioned.fill(
            child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => remoteTaps++,
        )),
        Align(
            alignment: Alignment.topLeft,
            child: _menu('光效', onDismiss: () => dismissals++)),
      ])),
    ));
    expect(_chip(tester, '光效').selected, isFalse);
    await tester.tap(find.text('光效'));
    await tester.pumpAndSettle();
    expect(find.byType(MiuGlass), findsOneWidget);
    expect(find.text('光效 设置'), findsOneWidget);
    expect(_chip(tester, '光效').selected, isTrue);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('光效 设置'), findsNothing);
    expect(_chip(tester, '光效').selected, isFalse);
    await tester.tap(find.text('光效'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.text('光效 设置'), findsNothing);
    expect(remoteTaps, 0);
    expect(dismissals, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('independent pet menu switches from glow in one click',
      (tester) async {
    var tasks = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
          body: MiuToolbarMenuBar(
              child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _menu('光效'),
          _menu('宠物'),
          MiuToolbarChip(
              icon: Icons.bolt_rounded, label: '任务', onPressed: () => tasks++)
        ],
      ))),
    ));
    await tester.tap(find.text('光效'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宠物'));
    await tester.pumpAndSettle();
    expect(find.text('光效 设置'), findsNothing);
    expect(find.text('宠物 设置'), findsOneWidget);
    expect(_chip(tester, '宠物').selected, isTrue);
    expect(_chip(tester, '光效').selected, isFalse);
    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(tasks, 1);
    expect(find.text('宠物 设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow menu stays on screen and long content can scroll',
      (tester) async {
    tester.view.physicalSize = const Size(320, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
          body: Align(
        alignment: Alignment.topRight,
        child: _menu('显示', long: true),
      )),
    ));
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(MiuGlass));
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.right, lessThanOrEqualTo(320));
    expect(panel.top, greaterThanOrEqualTo(0));
    expect(panel.bottom, lessThanOrEqualTo(360));
    await tester.scrollUntilVisible(find.text('显示 选项 17'), 180,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('显示 选项 17').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
