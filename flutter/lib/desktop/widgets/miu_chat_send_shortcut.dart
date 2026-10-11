import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MiuChatSendShortcut extends StatelessWidget {
  const MiuChatSendShortcut({
    super.key,
    required this.controller,
    required this.onSend,
    required this.child,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.ignored;
          }
          final keyboard = HardwareKeyboard.instance;
          final composing = controller.value.composing;
          if (keyboard.isControlPressed ||
              keyboard.isAltPressed ||
              keyboard.isMetaPressed ||
              (composing.isValid && !composing.isCollapsed)) {
            return KeyEventResult.ignored;
          }
          if (keyboard.isShiftPressed) {
            if (event is KeyDownEvent) {
              final value = controller.value;
              final selection = value.selection;
              final start =
                  selection.isValid ? selection.start : value.text.length;
              final end = selection.isValid ? selection.end : value.text.length;
              final text = value.text.replaceRange(start, end, '\n');
              if (text.characters.length <= 1000) {
                controller.value = TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: start + 1));
              }
            }
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent) onSend();
          return KeyEventResult.handled;
        },
        child: child,
      );
}
