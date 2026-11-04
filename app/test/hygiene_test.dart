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

  test('the board code joins no user-visible strings with a separator (ARB messages with placeholders instead)', () {
    for (final dir in ['lib/features/board', 'lib/features/report']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        expect(text, isNot(contains("join(' \u00b7 ')")), reason: f.path);
        expect(text, isNot(contains("join(' · ')")), reason: f.path);
        expect(RegExp(r"'\$\{?[a-z]+\}? \$\{?[a-z]+\}?'").hasMatch(text), isFalse, reason: '${f.path} concatenates two values into one string');
      }
    }
  });

  group('vendored chessground (third_party/chessground)', () {
    test('only board_assets.dart names PieceSet or ChessboardColorScheme (the removed assets stay unreachable)', () {
      final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'));
      for (final f in files) {
        if (f.path.endsWith('features/board/board_assets.dart')) continue;
        final text = f.readAsStringSync();
        expect(RegExp(r'\bPieceSet\b').hasMatch(text), isFalse, reason: f.path);
        expect(RegExp(r'\bChessboardColorScheme\b').hasMatch(text), isFalse, reason: f.path);
        expect(text, isNot(contains('horsey')), reason: f.path);
      }
    });

    test('the GPL notice of modifications exists and names the version and the changes', () {
      final notice = File('../third_party/chessground/NOTICE').readAsStringSync();
      expect(notice, startsWith('Modified copy of chessground 11.0.0'));
      expect(notice, contains('GNU General'));
      expect(notice, contains('pubspec.yaml'));
      expect(notice, contains('horsey'));
      expect(notice, contains('cburnett'));
      expect(notice, contains('UNCHANGED'));
      expect(File('../third_party/chessground/LICENSE').existsSync(), isTrue);
    });

    test('the vendoring script copies from an allow-list, and the tree is exactly that list', () {
      final script = File('../tool/vendor_chessground.sh').readAsStringSync();
      expect(script, contains('KEEP_PIECE_SETS=(cburnett)'));
      expect(script, isNot(contains('rm -f "\$DST"/assets/boards/horsey')));
      final listed = RegExp(r'KEEP_BOARDS=\(([^)]*)\)').firstMatch(script)!.group(1)!.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
      final boards = Directory('../third_party/chessground/assets/boards').listSync().map((e) => e.path.split('/').last).toSet();
      expect(boards, listed);
      final sets = Directory('../third_party/chessground/assets/piece_sets').listSync().map((e) => e.path.split('/').last).toSet();
      expect(sets, {'cburnett'});
      expect(boards.any((b) => b.startsWith('horsey')), isFalse);
    });
  });
}
