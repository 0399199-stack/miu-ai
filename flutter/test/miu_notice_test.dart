import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_notice.dart';

void main() {
  test('notice preserves multiline Unicode and validates timer and payload',
      () {
    final valid = const MiuNotice(title: '  提醒  ', text: '第一行\n第二行🐱').toJson();
    final parsed = MiuNotice.parse(valid)!;
    expect(parsed.title, '提醒');
    expect(parsed.text, '第一行\n第二行🐱');
    expect(parsed.seconds, 15);
    expect(parsed.sound, isTrue);
    expect(parsed.textColor, MiuNotice.defaultTextColor);
    expect(
        MiuNotice.parse({...valid, 'textColor': '#ad2356'})!
            .toJson()['textColor'],
        '#AD2356');
    final legacy = {...valid}..remove('textColor');
    expect(MiuNotice.parse(legacy)!.textColor, MiuNotice.defaultTextColor);
    for (final change in <Map<String, dynamic>>[
      {'title': ''},
      {'title': 'x' * 61},
      {'title': 'a\nb'},
      {'text': ' '},
      {'text': 'x' * 1201},
      {'text': 'a\u0000b'},
      {'seconds': 0},
      {'seconds': 301},
      {'seconds': 1.5},
      {'sound': 'true'},
      {'textColor': null},
      {'textColor': '#F00'},
      {'textColor': '#FF000080'},
      {'textColor': 'red'},
    ]) {
      expect(MiuNotice.parse({...valid, ...change}), isNull, reason: '$change');
    }
    expect(
        MiuNotice.parse({
          ...valid,
          'title': 'x' * 60,
          'text': 'x' * 1200,
          'seconds': 300,
          'sound': false
        }),
        isNotNull);
  });

  test('native launch failure cannot be reported as a displayed notice',
      () async {
    final host = MiuNoticeHost('missing-miu-notice-window.exe');
    expect(await host.show(const MiuNotice(title: '提醒', text: '正文')), isFalse);
  });
}
