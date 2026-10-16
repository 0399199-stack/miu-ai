import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/widgets/miu_controller_header.dart';

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
}
