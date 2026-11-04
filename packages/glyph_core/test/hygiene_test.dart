import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('glyph_core has no Flutter imports and no print()', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('package:flutter')), reason: f.path);
      expect(text, isNot(contains('dart:ui')), reason: f.path);
      expect(RegExp(r'(^|[^A-Za-z_.])print\(').hasMatch(text), isFalse, reason: f.path);
    }
  });
}
