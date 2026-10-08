import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_ai_history.dart';

void main() {
  test('B keeps a bounded recent conversation across restarts', () async {
    var option = '';
    MiuAiHistoryStore store() => MiuAiHistoryStore.forTesting(
          read: () => option,
          write: (value) async => option = value,
        );
    final first = store();
    for (var i = 0; i < 30; i++) {
      await first.add('message $i', fromUser: i.isEven);
    }
    expect(first.recent, hasLength(24));
    expect(first.recent.first.text, 'message 29');
    final afterRestart = store();
    expect(afterRestart.recent, hasLength(24));
    expect(afterRestart.recent.first.fromUser, isFalse);
    expect(afterRestart.recent.last.text, 'message 6');
    expect(option, isNot(contains('sk-test-key')));
  });

  test('long Unicode turns sync in bounded pages without loss', () async {
    var option = '';
    final store = MiuAiHistoryStore.forTesting(
      read: () => option,
      write: (value) async => option = value,
    );
    final longText = '你好😀' * 900;
    await store.add('先问问题', fromUser: true);
    await store.add(longText, fromUser: false);
    int? before;
    var offset = 0;
    final rebuilt = <String>[];
    var partial = '';
    for (var i = 0; i < 12; i++) {
      final page = store.page(before: before, offset: offset);
      expect(utf8.encode(jsonEncode(page)).length, lessThan(3200));
      for (final entry in page['entries'] as List) {
        partial += entry['text'] as String;
        if (entry['complete'] == true) {
          rebuilt.add(partial);
          partial = '';
        }
      }
      if (page['done'] == true) break;
      before = page['nextBefore'] as int;
      offset = page['nextOffset'] as int;
    }
    expect(rebuilt, [longText, '先问问题']);
  });

  test('failed local persistence does not interrupt chatting', () async {
    final store = MiuAiHistoryStore.forTesting(
      read: () => '',
      write: (_) async => throw StateError('disk failure'),
    );
    await store.add('hi', fromUser: true);
    expect(store.recent.single.text, 'hi');
  });

  test('all 24 maximum-length turns fit the sync page limit', () async {
    var option = '';
    final store = MiuAiHistoryStore.forTesting(
      read: () => option,
      write: (value) async => option = value,
    );
    for (var i = 0; i < 24; i++) {
      await store.add('中' * 4000, fromUser: i.isEven);
    }
    int? before;
    var offset = 0;
    var pages = 0;
    var complete = 0;
    while (pages < 160) {
      final page = store.page(before: before, offset: offset);
      expect(utf8.encode(jsonEncode(page)).length, lessThan(3200));
      pages++;
      complete += (page['entries'] as List)
          .where((entry) => entry['complete'] == true)
          .length;
      if (page['done'] == true) break;
      before = page['nextBefore'] as int;
      offset = page['nextOffset'] as int;
    }
    expect(complete, 24);
    expect(pages, lessThan(160));
  });
}
