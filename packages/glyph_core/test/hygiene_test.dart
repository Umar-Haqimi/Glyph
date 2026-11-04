import 'dart:io';

import 'package:test/test.dart';

Iterable<File> sources(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('glyph_core has no Flutter imports and no print()', () {
    final files = sources('lib');
    expect(files, isNotEmpty);
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('package:flutter')), reason: f.path);
      expect(text, isNot(contains('dart:ui')), reason: f.path);
      expect(RegExp(r'(^|[^A-Za-z_.])print\(').hasMatch(text), isFalse, reason: f.path);
    }
  });

  group('API key hygiene (SPEC 6)', () {
    test('"Authorization" and "Bearer" appear only in the LLM client', () {
      for (final f in sources('lib')) {
        if (f.path.endsWith('src/llm/llm_client.dart')) continue;
        expect(RegExp('authorization|bearer', caseSensitive: false).hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('the key is interpolated into exactly one string: the Authorization header', () {
      final text = File('lib/src/llm/llm_client.dart').readAsStringSync();
      final uses = RegExp(r'''['"][^'"\n]*\$\{?key\}?[^'"\n]*['"]''').allMatches(text).map((m) => m.group(0)).toList();
      expect(uses, [r"'Bearer $key'"]);
    });

    test('the core never logs: no dart:developer, no stdout / stderr, no debugPrint', () {
      for (final f in sources('lib')) {
        if (f.path.endsWith('glyph_core_host.dart') || f.path.contains('process_engine_driver')) continue;
        final text = f.readAsStringSync();
        expect(text, isNot(contains('dart:developer')), reason: f.path);
        expect(RegExp(r'\b(stdout|stderr)\.').hasMatch(text), isFalse, reason: f.path);
        expect(text, isNot(contains('debugPrint')), reason: f.path);
      }
    });

    test('LlmRequest and LlmConfig have no API key field', () {
      final code = File('lib/src/llm/llm_models.dart').readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(RegExp('apiKey|api_key|secret', caseSensitive: false).hasMatch(code), isFalse);
    });
  });

  group('online clients (SPEC 6)', () {
    test('hosts are hard-coded https; a User-Agent is passed in, never built from user data', () {
      for (final name in ['lichess_client', 'chesscom_client']) {
        final text = File('lib/src/online/$name.dart').readAsStringSync();
        expect(text, contains("defaultBaseUrl = 'https://"), reason: name);
        expect(text, isNot(contains("'http://")), reason: name);
      }
      final transport = File('lib/src/online/online_transport.dart').readAsStringSync();
      expect(RegExp(r"'User-Agent': userAgent").hasMatch(transport), isTrue);
      // The only header values the clients set are fixed strings or the ETag.
      for (final f in sources('lib/src/online')) {
        final text = f.readAsStringSync();
        expect(RegExp('mailto|@[a-z]+\\.(com|org)', caseSensitive: false).hasMatch(text), isFalse, reason: f.path);
        expect(text, isNot(contains('dart:io')), reason: f.path);
        expect(RegExp('cookie|authorization', caseSensitive: false).hasMatch(text), isFalse, reason: f.path);
      }
    });
  });
}
