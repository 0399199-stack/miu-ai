import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_chat_send_shortcut.dart';

void main() {
  testWidgets('Enter sends once; Shift+Enter inserts a newline',
      (tester) async {
    final input = TextEditingController();
    final sent = <String>[];
    addTearDown(input.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: MiuChatSendShortcut(
        controller: input,
        onSend: () {
          sent.add(input.text);
          input.clear();
        },
        child: TextField(
            controller: input,
            minLines: 1,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline),
      ),
    )));
    await tester.enterText(find.byType(TextField), '你好 Miu');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    expect(sent, ['你好 Miu']);
    expect(input.text, isEmpty);
    await tester.enterText(find.byType(TextField), '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(input.text, '第一行\n');
    expect(sent, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Enter preserves IME composition before sending', (tester) async {
    final input = TextEditingController();
    var sends = 0;
    addTearDown(input.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: MiuChatSendShortcut(
        controller: input,
        onSend: () => sends++,
        child: TextField(controller: input, maxLines: 5),
      ),
    )));
    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'nihao',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sends, 0);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '你好',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(sends, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
