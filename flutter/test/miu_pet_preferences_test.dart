import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_pet_preferences.dart';

void main() {
  test('B preferences default off and survive refresh without changing persona',
      () async {
    final options = <String, String>{'miu-ai-persona': '保留我的人设'};
    MiuPetPreferences create() => MiuPetPreferences.forTesting(
        read: (key) => options[key] ?? '',
        write: (key, value) async => options[key] = value);
    final preferences = create()..refresh();
    addTearDown(preferences.dispose);
    expect(preferences.character, 'luna');
    expect(preferences.proactiveEnabled, isFalse);
    await preferences.set(character: 'void', proactiveEnabled: true);
    final restarted = create()..refresh();
    addTearDown(restarted.dispose);
    expect(restarted.character, 'void');
    expect(restarted.proactiveEnabled, isTrue);
    expect(options['miu-ai-persona'], '保留我的人设');
    await expectLater(
        preferences.set(character: 'invalid'), throwsFormatException);
    expect(preferences.character, 'void');
    options['miu-pet-proactive-enabled'] = 'N';
    preferences.refresh();
    expect(preferences.proactiveEnabled, isFalse);
  });
}
