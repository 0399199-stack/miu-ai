import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/desktop/widgets/miu_glass.dart';
import 'package:flutter_hbb/desktop/widgets/miu_task_center.dart';
import 'package:flutter_hbb/models/model.dart';

class _FakeFFI implements FFI {
  @override
  String id = '123456789';
  @override
  bool closed = false;
  @override
  ConnType connType = ConnType.defaultConn;
  @override
  FfiModel ffiModel = _FakeFfiModel();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeFfiModel implements FfiModel {
  @override
  bool keyboard = false;
  @override
  bool isPeerWindows = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('task center leaves remote view usable and stays in bounds',
      (tester) async {
    PrivacyModeState.init('123456789');
    addTearDown(() => PrivacyModeState.delete('123456789'));
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    OverlayEntry? entry;
    var remoteTaps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 28),
          Expanded(
            child: Overlay(initialEntries: [
              OverlayEntry(
                  builder: (context) => Stack(children: [
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => remoteTaps++,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            entry = showMiuTaskCenter(context, _FakeFFI(), () {
                              entry?.remove();
                              entry?.dispose();
                              entry = null;
                            });
                          },
                          child: const Text('Open'),
                        ),
                      ]))
            ]),
          ),
        ]),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MiuBackdrop)), const Size(520, 480));

    await tester.tapAt(const Offset(750, 550));
    await tester.pump();
    expect(remoteTaps, 1);

    final before = tester.getTopLeft(find.byType(MiuBackdrop));
    await tester.drag(find.text('任务中心'), const Offset(0, 40));
    await tester.pump();
    final after = tester.getTopLeft(find.byType(MiuBackdrop));
    expect(after, before + const Offset(0, 40));

    tester.view.physicalSize = const Size(440, 360);
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(MiuBackdrop));
    expect(panel.size, const Size(416, 308));
    expect(panel.left, greaterThanOrEqualTo(0));
    expect(panel.top, greaterThanOrEqualTo(28));
    expect(panel.right, lessThanOrEqualTo(440));
    expect(panel.bottom, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.byType(MiuBackdrop), findsNothing);
  });
}
