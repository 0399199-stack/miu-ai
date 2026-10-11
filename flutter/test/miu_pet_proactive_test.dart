import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_pet_proactive.dart';

class _Intervals implements Random {
  final values = [0, 3600, 1800];
  int index = 0;
  @override
  int nextInt(int max) {
    expectSync(max, 3601);
    return values[(index++) % values.length];
  }
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

void main() {
  testWidgets('companionship waits 30–90 minutes and schedules a fresh interval', (tester) async {
    var calls = 0;
    final timer = MiuPetProactiveTimer(random: _Intervals(), onDue: () async { calls++; });
    timer.update(true);
    await tester.pump(const Duration(minutes: 29));
    expect(calls, 0);
    timer.update(true); // State refresh does not shorten or restart the slot.
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 89));
    expect(calls, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
    timer.dispose();
  });

  testWidgets('disabled and hidden pet cancels all pending opportunities', (tester) async {
    var calls = 0;
    final timer = MiuPetProactiveTimer(random: _Intervals(), onDue: () async { calls++; });
    await tester.pump(const Duration(hours: 2));
    expect(calls, 0); // Default is off.
    timer.update(true);
    await tester.pump(const Duration(minutes: 10));
    timer.update(false);
    await tester.pump(const Duration(hours: 2));
    expect(calls, 0);
    timer.update(true);
    timer.dispose(); // Host teardown, including hidden pet, cancels the slot.
    await tester.pump(const Duration(hours: 2));
    expect(calls, 0);
  });
}
