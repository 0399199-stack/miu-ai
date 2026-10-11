import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_pet_control_panel.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';

class _Chat extends ChangeNotifier implements ChatModel {
  @override
  String? miuPetCharacter = 'luna';
  @override
  bool? miuPetProactiveEnabled = false;
  @override
  bool get miuPetVisible => true;
  @override
  bool get miuPetAiEnabled => true;
  final changes = <(String, bool)>[];
  @override
  Future<bool> setMiuPetPreferences({required String character,
      required bool proactiveEnabled}) async {
    changes.add((character, proactiveEnabled));
    miuPetCharacter = character;
    miuPetProactiveEnabled = proactiveEnabled;
    notifyListeners();
    return true;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Peer extends ChangeNotifier implements FfiModel {
  @override
  bool get miuPeerAuthenticated => true;
  @override
  bool get isPeerWindows => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Session implements FFI {
  _Session(this.chatModel, this.ffiModel);
  @override
  final _Chat chatModel;
  @override
  final _Peer ffiModel;
  @override
  bool get closed => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Future<_Chat> mount(WidgetTester tester, {bool supported = true}) async {
    final chat = _Chat();
    final peer = _Peer();
    if (!supported) {
      chat.miuPetCharacter = null;
      chat.miuPetProactiveEnabled = null;
    }
    addTearDown(chat.dispose);
    addTearDown(peer.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        SingleChildScrollView(child: SizedBox(width: 340,
          child: MiuPetControlPanel(ffi: _Session(chat, peer),
            onClose: () {}, onChat: () {}, onSettings: () {}))))));
    return chat;
  }

  testWidgets('A selects the pet and toggles proactive chat without changing the other preference', (tester) async {
    final chat = await mount(tester);
    await tester.tap(find.text('Miu Void'));
    await tester.pump();
    expect(chat.changes, [('void', false)]);
    await tester.ensureVisible(find.text('随机互动'));
    await tester.tap(find.text('随机互动'));
    await tester.pump();
    expect(chat.changes.last, ('void', true));
    expect(find.text('DeepSeek 生成 · 每 30–90 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('older B does not expose a working pet preference switch', (tester) async {
    final chat = await mount(tester, supported: false);
    await tester.tap(find.text('Miu Void'));
    await tester.ensureVisible(find.text('随机互动'));
    await tester.tap(find.text('随机互动'));
    await tester.pump();
    expect(chat.changes, isEmpty);
    expect(find.text('角色切换需新版 B 机支持'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
