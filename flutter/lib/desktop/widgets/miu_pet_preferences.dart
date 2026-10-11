import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';

String normalizeMiuPetCharacter(String value) =>
    value == 'void' ? 'void' : 'luna';

String miuPetCharacterStyle(String character) => character == 'void'
    ? '当前角色是 Miu Void，一只冷酷、机灵、带战斗风格的桌面小猫。'
        '说话简短利落，偶尔毒舌或轻微调侃，但不羞辱用户、不威胁或鼓励现实伤害。'
    : '当前角色是 Miu Luna，一只温柔、聪明、善于陪伴的蓝白桌面小猫。'
        '说话自然体贴，偶尔俏皮，不用客服套话或重复卖萌。';

class MiuPetPreferences extends ChangeNotifier {
  MiuPetPreferences._()
      : _read = ((key) => bind.mainGetLocalOption(key: key)),
        _write =
            ((key, value) => bind.mainSetLocalOption(key: key, value: value));

  @visibleForTesting
  MiuPetPreferences.forTesting({
    required String Function(String) read,
    required Future<void> Function(String, String) write,
  })  : _read = read,
        _write = write;

  static final instance = MiuPetPreferences._();
  final String Function(String) _read;
  final Future<void> Function(String, String) _write;
  String _character = 'luna';
  bool _proactiveEnabled = false;
  int _revision = 0;

  String get character => _character;
  bool get proactiveEnabled => _proactiveEnabled;
  int get revision => _revision;

  void refresh() {
    final character = normalizeMiuPetCharacter(_read('miu-pet-character'));
    final proactiveEnabled = _read('miu-pet-proactive-enabled') == 'Y';
    if (character == _character && proactiveEnabled == _proactiveEnabled) {
      return;
    }
    _character = character;
    _proactiveEnabled = proactiveEnabled;
    _revision++;
    notifyListeners();
  }

  Future<void> set({String? character, bool? proactiveEnabled}) async {
    if (character != null && character != 'luna' && character != 'void') {
      throw const FormatException('未知的宠物角色');
    }
    try {
      if (character != null) await _write('miu-pet-character', character);
      if (proactiveEnabled != null) {
        await _write('miu-pet-proactive-enabled', proactiveEnabled ? 'Y' : 'N');
      }
    } finally {
      refresh();
    }
  }
}
