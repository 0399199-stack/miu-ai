import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_boot_player.dart';

void main() {
  test('B saves preset/custom colors and reads actual settings after restart',
      () async {
    var stored = '';
    MiuBootPlayer create() => MiuBootPlayer.forTesting(
        read: () => stored,
        write: (value) async {
          stored = value;
        },
        launch: (_) async => true);
    final player = create();
    expect(await player.save({'color': '#FF0000', 'autoPlay': true}), isTrue);
    expect(create().settings.color, '#FF0000');
    expect(await player.save({'color': '#12abef', 'autoPlay': false}), isTrue);
    expect(create().settings.toJson(), {'color': '#12ABEF', 'autoPlay': false});
    final before = stored;
    expect(await player.save({'color': 'red;run', 'autoPlay': true}), isFalse);
    expect(
        await player.save({'color': '#FFFFFF', 'autoPlay': 'true'}), isFalse);
    expect(stored, before);
  });

  test('disabled login skips launch; explicit play still uses B saved color',
      () async {
    var stored = jsonEncode({'color': '#FF0000', 'autoPlay': false});
    final launched = <String>[];
    final player = MiuBootPlayer.forTesting(
        read: () => stored,
        write: (value) async {
          stored = value;
        },
        launch: (color) async {
          launched.add(color);
          return true;
        });
    expect(await player.play(atLogin: true), isFalse);
    expect(launched, isEmpty);
    expect(await player.play(), isTrue);
    expect(launched, ['#FF0000']);
    await player.save({'color': '#A56CFF', 'autoPlay': true});
    expect(await player.play(atLogin: true), isTrue);
    expect(launched.last, '#A56CFF');
  });

  test('failed save/start is reported, not claimed as success', () async {
    final player = MiuBootPlayer.forTesting(
        read: () => '',
        write: (_) async {
          throw StateError('write failed');
        },
        launch: (_) async => false);
    expect(await player.save({'color': '#FFFFFF', 'autoPlay': true}), isFalse);
    expect(await player.play(), isFalse);
    expect(player.settings.color, '#48AAFF');
  });
}
