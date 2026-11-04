import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app/lib has no print() and no hard-coded Text literals', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'));
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(RegExp(r'(^|[^A-Za-z_.])print\(').hasMatch(text), isFalse, reason: f.path);
      expect(RegExp('''Text\\(\\s*['"]''').hasMatch(text), isFalse, reason: '${f.path} has a literal in Text(...)');
    }
  });

  test('production code never imports the glyph_core testing library', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains("import 'package:glyph_core/testing.dart'")), reason: f.path);
    }
  });
}
