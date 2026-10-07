import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/desktop/widgets/miu_ai_credentials.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Windows Credential Manager stores and removes the API key', () {
    if (!Platform.isWindows) return;
    final store =
        MiuAiCredentialStore(target: 'MiuAI/Test/${const Uuid().v4()}');
    try {
      store.write('sk-local-test-only');
      expect(store.read(), 'sk-local-test-only');
    } finally {
      store.delete();
    }
    expect(store.read(), isNull);
  });
}
