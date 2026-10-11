import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_pet_chat.dart';
import 'package:flutter_hbb/desktop/widgets/miu_ai_chat.dart';
import 'package:flutter_hbb/models/chat_model.dart';

class _ChatModel extends ChangeNotifier implements ChatModel {
  int unread = 0;
  @override
  final messages = <MessageKey, MessageBody>{};
  @override
  final me = ChatUser(id: 'me');

  @override
  int miuUnreadCount(MessageKey key) => unread;

  void pushUnread([String text = '收到新消息']) {
    final sender = ChatUser(id: 'A');
    final body = messages.putIfAbsent(
        MessageKey('peer', 1), () => MessageBody(sender, []));
    body.insert(
        ChatMessage(user: sender, createdAt: DateTime.now(), text: text));
    unread++;
    notifyListeners();
  }

  void clearUnread() {
    unread = 0;
    notifyListeners();
  }

  @override
  void markMiuRead(MessageKey key) {
    if (unread > 0) clearUnread();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('offline B pet opens AI chat and can close it', (tester) async {
    final chat = _ChatModel();
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
          child: SizedBox(
        width: 360,
        height: 450,
        child: MiuPetHost(
          chatModel: chat,
          keyForPeer: MessageKey('', -2),
          chatAvailable: false,
          onExpanded: (_) async {},
        ),
      )),
    ));
    await tester.tapAt(
        tester.getBottomRight(find.byType(MiuPetHost)) - const Offset(80, 80));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MiuAiChatView), findsOneWidget);
    expect(find.text('Miu AI'), findsOneWidget);
    expect(find.text('Terminal'), findsNothing);
    await tester.tap(find.byTooltip('关闭聊天'));
    await tester.pump();
    expect(find.byType(MiuAiChatView), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('connected pet shows distinct AI and Terminal tabs',
      (tester) async {
    final chat = _ChatModel();
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
          child: SizedBox(
        width: 520,
        height: 700,
        child: MiuPetHost(
          chatModel: chat,
          keyForPeer: MessageKey('peer', 1),
          onExpanded: (_) async {},
        ),
      )),
    ));
    await tester.tapAt(
        tester.getBottomRight(find.byType(MiuPetHost)) - const Offset(80, 80));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Miu AI'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.byTooltip('关闭聊天'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pet shows an obvious notice for unread messages',
      (tester) async {
    final chat = _ChatModel();
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 196,
          height: 192,
          child: MiuPetHost(
            chatModel: chat,
            keyForPeer: MessageKey('peer', 1),
            onExpanded: (_) async {},
          ),
        ),
      ),
    ));

    expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0);
    chat.pushUnread();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('收到新消息'), findsOneWidget);
    expect(find.byIcon(Icons.mark_chat_unread_rounded), findsOneWidget);

    chat.pushUnread();
    await tester.pump();
    expect(find.text('2 条'), findsOneWidget);

    chat.clearUnread();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('message bubble previews text and opens Terminal chat',
      (tester) async {
    final chat = _ChatModel();
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox(
      width: 520,
      height: 700,
      child: MiuPetHost(
          chatModel: chat,
          keyForPeer: MessageKey('peer', 1),
          onExpanded: (_) async {}),
    ))));
    chat.pushUnread('文件已经准备好了，点这里查看消息');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('文件已经准备好了，点这里查看消息'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('miu-pet-message-notice')));
    await tester.pump();
    expect(find.byType(MiuChatView), findsOneWidget);
    expect(find.byType(MiuAiChatView), findsNothing);
    expect(find.byTooltip('关闭聊天'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('image notification does not display the image payload',
      (tester) async {
    final chat = _ChatModel();
    addTearDown(chat.dispose);
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
      width: 196,
      height: 192,
      child: MiuPetHost(
          chatModel: chat,
          keyForPeer: MessageKey('peer', 1),
          onExpanded: (_) async {}),
    )));
    chat.pushUnread('miu:image/jpeg;base64,test-image-payload');
    await tester.pump();
    expect(find.text('收到图片'), findsOneWidget);
    expect(find.textContaining('test-image-payload'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
