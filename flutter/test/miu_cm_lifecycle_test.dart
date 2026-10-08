import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/pages/server_page.dart';

void main() {
  test('Windows Miu host keeps pet alive after last remote tab closes', () {
    expect(
      shouldCloseCmAfterTabRemoval(
          hasTabs: false, isWindows: true, appName: 'MiuAI'),
      isFalse,
    );
    expect(
      shouldCloseCmAfterTabRemoval(
          hasTabs: true, isWindows: true, appName: 'MiuAI'),
      isFalse,
    );
  });

  test('other connection managers still close after last tab', () {
    expect(
      shouldCloseCmAfterTabRemoval(
          hasTabs: false, isWindows: true, appName: 'RustDesk'),
      isTrue,
    );
    expect(
      shouldCloseCmAfterTabRemoval(
          hasTabs: false, isWindows: false, appName: 'MiuAI'),
      isTrue,
    );
  });
}
