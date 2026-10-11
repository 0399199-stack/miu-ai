import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_home_device.dart';

void main() {
  testWidgets(
      'device card keeps connect, viewing and nickname actions distinct',
      (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: MiuHomeDevice(
            name: '工作室电脑',
            id: '100 200 300',
            details: 'Windows',
            onConnect: () => actions.add('connect'),
            onView: () => actions.add('view'),
            onRename: () => actions.add('rename'),
            menu: IconButton(
              tooltip: '更多设备操作',
              onPressed: () => actions.add('menu'),
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('连接'));
    await tester.tap(find.text('仅观看'));
    await tester.tap(find.byTooltip('设置备注'));
    await tester.tap(find.byTooltip('更多设备操作'));
    expect(actions, ['connect', 'view', 'rename', 'menu']);
    expect(find.text('最近连接'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long device names fit both compact list and narrow card',
      (tester) async {
    for (final compact in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.25)),
          child: Scaffold(
            body: SizedBox(
              width: compact ? 580 : 276,
              child: MiuHomeDevice(
                compact: compact,
                name: '这是一台备注名称很长的工作室剪辑电脑',
                id: '100 200 300',
                details: 'Windows · desktop-workstation',
                onConnect: () {},
                onView: () {},
                onRename: () {},
                menu: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz_rounded)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('连接'), findsOneWidget);
      expect(find.text('仅观看'), findsOneWidget);
    }
  });
}
