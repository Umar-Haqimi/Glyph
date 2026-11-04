import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/platform/app_log.dart';

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

  group('API keys and the network (SPEC 6)', () {
    Iterable<File> sources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'));

    test('"Authorization" and "Bearer" never appear in the app (the header is set in glyph_core)', () {
      for (final f in sources()) {
        expect(RegExp('authorization|bearer', caseSensitive: false).hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('flutter_secure_storage is used by one file only', () {
      for (final f in sources()) {
        if (f.path.endsWith('platform/secret_store.dart')) continue;
        expect(f.readAsStringSync(), isNot(contains('flutter_secure_storage')), reason: f.path);
      }
    });

    test('the only file that opens a network connection is platform/llm_http.dart', () {
      for (final f in sources()) {
        if (f.path.endsWith('platform/llm_http.dart')) continue;
        final text = f.readAsStringSync();
        expect(text, isNot(contains('package:http/')), reason: f.path);
        expect(RegExp(r'\b(HttpClient|WebSocket|RawSocket|Socket\.connect)\b').hasMatch(text), isFalse, reason: f.path);
      }
    });

    test('logging goes through AppLog only, and AppLog calls never pass key-like or text-like values', () {
      for (final f in sources()) {
        final text = f.readAsStringSync();
        if (!f.path.endsWith('platform/app_log.dart')) {
          expect(text, isNot(contains('dart:developer')), reason: f.path);
          expect(RegExp(r'\b(debugPrint|developer\.log|log)\(').hasMatch(text.replaceAll('AppLog.warning(', '')), isFalse, reason: f.path);
        }
        for (final call in RegExp(r'AppLog\.warning\(([^;]*?)\);', dotAll: true).allMatches(text)) {
          // Drop string literals: the message is a fixed sentence and may say "API key".
          final code = call.group(1)!.replaceAll(RegExp(r''''[^']*'|"[^"]*"'''), '');
          expect(
            RegExp(r'key|secret|token|password|auth|bearer|prompt|body|content|text|detail|message|toString|\$', caseSensitive: false).hasMatch(code),
            isFalse,
            reason: '${f.path}: AppLog.warning(${call.group(1)}) must pass only the error object',
          );
        }
      }
    });

    test('settings are written without anything key-like', () {
      for (final f in sources()) {
        for (final call in RegExp(r'\.(set|remove)\(([^;]*?)\);', dotAll: true).allMatches(f.readAsStringSync())) {
          final args = call.group(2)!;
          if (!args.contains('SettingsKeys.') && !args.contains('key')) continue;
          expect(RegExp(r'apiKey|secret|password|bearer', caseSensitive: false).hasMatch(args), isFalse, reason: '${f.path}: ${call.group(0)}');
        }
      }
    });

    test('the API key is never put in widget state, a provider state or a notifier field', () {
      // The only places that name a key value are the secret store, the
      // settings notifier that masks it, and the form field controller; the
      // request code handles the reader function only.
      final allowed = {
        'platform/secret_store.dart',
        'features/settings/explain_settings.dart',
        'features/settings/llm_settings_screen.dart',
        // These pass the *reader function* (`readApiKey`) to the client, never a key.
        'features/explain/generation.dart',
        'features/explain/explain_controller.dart',
        'features/explain/summary_controller.dart',
        'features/settings/key_vault.dart',
      };
      for (final f in sources()) {
        final path = f.path.replaceFirst('lib/', '');
        if (allowed.contains(path)) continue;
        expect(RegExp(r'\bapiKey\b|readApiKey', caseSensitive: false).hasMatch(f.readAsStringSync()), isFalse, reason: path);
      }
    });

    test('AppLog records only the error type', () {
      final lines = <String>[];
      final old = AppLog.sink;
      AppLog.sink = lines.add;
      addTearDown(() => AppLog.sink = old);
      AppLog.warning('Reading the API key failed', Exception('Bearer sk-secret-123 and a prompt'));
      expect(lines, ['Reading the API key failed (_Exception)']);
    });
  });
}
