import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app_info.dart';
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
      for (final set in ['cburnett', 'merida', 'mpchess', 'rhosgfx']) {
        expect(notice, contains(set));
      }
      expect(notice, contains('UNCHANGED'));
      expect(File('../third_party/chessground/LICENSE').existsSync(), isTrue);
    });

    test('the vendoring script copies from an allow-list, and the tree is exactly that list', () {
      final script = File('../tool/vendor_chessground.sh').readAsStringSync();
      final listedSets = RegExp(r'KEEP_PIECE_SETS=\(([^)]*)\)').firstMatch(script)!.group(1)!.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
      expect(listedSets, {'cburnett', 'merida', 'mpchess', 'rhosgfx'});
      expect(script, isNot(contains('rm -f "\$DST"/assets/boards/horsey')));
      final listed = RegExp(r'KEEP_BOARDS=\(([^)]*)\)').firstMatch(script)!.group(1)!.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
      final boards = Directory('../third_party/chessground/assets/boards').listSync().map((e) => e.path.split('/').last).toSet();
      expect(boards, listed);
      final sets = Directory('../third_party/chessground/assets/piece_sets').listSync().map((e) => e.path.split('/').last).toSet();
      expect(sets, listedSets);
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

    test('the only files that open a network connection are platform/llm_http.dart (the LLM) and platform/online_http.dart (lichess, chess.com)', () {
      for (final f in sources()) {
        if (f.path.endsWith('platform/llm_http.dart') || f.path.endsWith('platform/online_http.dart')) continue;
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

  group('online requests (SPEC 6)', () {
    test('appVersion matches pubspec.yaml and the User-Agent is a generic client name with the repository URL', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(RegExp(r'^version: (\d+\.\d+\.\d+)\+', multiLine: true).firstMatch(pubspec)!.group(1), appVersion);
      expect(onlineUserAgent, 'Glyph/$appVersion (+$projectUrl)');
      expect(onlineUserAgent, isNot(contains('@')));
      expect(projectUrl, startsWith('https://github.com/'));
    });

    test('the hosts are not named outside the core clients (no URL building in the app)', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'))) {
        final text = f.readAsStringSync();
        expect(RegExp(r'https?://(lichess\.org|api\.chess\.com)').hasMatch(text), isFalse, reason: f.path);
      }
    });

    test('usernames and URLs are never logged: the fetch code passes AppLog only the error object', () {
      for (final name in ['features/import/online_import_controller.dart', 'features/import/online_import_screen.dart']) {
        final text = File('lib/$name').readAsStringSync();
        expect(RegExp(r'\b(debugPrint|log)\(').hasMatch(text), isFalse, reason: name);
      }
    });
  });

  group('no logging beyond AppLog, no telemetry (SPEC 6, M8)', () {
    Iterable<File> dartFiles(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/app_localizations'));

    test('nothing in app/lib or packages/glyph_core/lib prints or logs except AppLog (and the host-only engine driver)', () {
      final banned = RegExp(r'(^|[^A-Za-z_.])(print|debugPrint|debugPrintStack|log|dumpErrorToConsole)\(|developer\.(log|inspect)|\b(stdout|stderr)\.|dart:developer|FlutterError\.dumpErrorToConsole|\bdebugger\(');
      for (final f in [...dartFiles('lib'), ...dartFiles('../packages/glyph_core/lib')]) {
        if (f.path.endsWith('platform/app_log.dart')) continue;
        if (f.path.endsWith('glyph_core_host.dart') || f.path.endsWith('process_engine_driver.dart')) continue;
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///')).join('\n');
        final m = banned.firstMatch(code);
        expect(m, isNull, reason: '${f.path}: ${m?.group(0)}');
      }
    });

    test('the Kotlin sources do not log either (no android.util.Log, println, printStackTrace)', () {
      final files = Directory('android/app/src/main').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt') || (f.path.endsWith('.java') && !f.path.endsWith('GeneratedPluginRegistrant.java')));
      expect(files, isNotEmpty);
      for (final f in files) {
        final code = f.readAsStringSync();
        expect(RegExp(r'android\.util\.Log|\bLog\.[a-z]\(|println\(|printStackTrace|Timber').hasMatch(code), isFalse, reason: f.path);
      }
    });

    test('the only thing AppLog can do is warn, with a fixed message and the error type', () {
      final code = File('lib/platform/app_log.dart').readAsStringSync();
      // One public entry point, and it is at warning level (900) or above: release logs nothing quieter.
      expect(RegExp(r'static void (?!Function)(\w+)\(').allMatches(code).map((m) => m.group(1)).toList(), ['warning']);
      expect(code, contains('level: 900'));
      expect(code, contains('error.runtimeType'));
      expect(code, isNot(contains('error.toString')));
      expect(code, isNot(contains(r"$error")));
      expect(code, isNot(contains('stackTrace')));
    });

    test('AppLog survives an error whose toString throws and never prints its text', () {
      final lines = <String>[];
      final old = AppLog.sink;
      AppLog.sink = lines.add;
      addTearDown(() => AppLog.sink = old);
      AppLog.warning('Something failed', _Hostile());
      expect(lines, ['Something failed (_Hostile)']);
      expect(lines.single, isNot(contains('sk-')));
    });

    test('no pubspec in the repository names an analytics, crash-reporting or ads package', () {
      final banned = RegExp(r'^\s+(firebase\w*|sentry\w*|bugsnag\w*|crashlytics|google_mobile_ads|google_analytics\w*|mixpanel\w*|amplitude\w*|appsflyer\w*|posthog\w*|datadog\w*|instabug\w*|onesignal\w*|facebook\w*|appcenter\w*):', multiLine: true);
      for (final path in ['pubspec.yaml', '../pubspec.yaml', '../packages/glyph_core/pubspec.yaml', '../pubspec.lock']) {
        expect(banned.hasMatch(File(path).readAsStringSync()), isFalse, reason: path);
      }
    });

    test('the Android build has no Firebase, Play Services or crash SDK', () {
      final files = Directory('android').listSync(recursive: true).whereType<File>().where((f) {
        final p = f.path;
        return !p.contains('/build/') && !p.contains('/.gradle/') && (p.endsWith('.gradle') || p.endsWith('.kts') || p.endsWith('AndroidManifest.xml') || p.endsWith('gradle.properties'));
      });
      expect(files, isNotEmpty);
      for (final f in files) {
        final code = f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('#')).join('\n');
        expect(RegExp('firebase|play-services|com\\.google\\.android\\.gms|crashlytics|io\\.sentry|bugsnag', caseSensitive: false).hasMatch(code), isFalse, reason: f.path);
      }
    });

    group('tool/check_banned_deps.sh', () {
      Future<ProcessResult> run(Directory root) => Process.run('bash', ['../tool/check_banned_deps.sh', root.path]);

      Directory tree(Map<String, String> files) {
        final dir = Directory.systemTemp.createTempSync('glyph_banned');
        addTearDown(() => dir.deleteSync(recursive: true));
        files.forEach((path, content) {
          File('${dir.path}/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(content);
        });
        return dir;
      }

      const cleanLock = 'packages:\n  http:\n    dependency: direct main\n  crypto:\n    dependency: transitive\n';

      test('passes on this repository', () async {
        final r = await Process.run('bash', ['../tool/check_banned_deps.sh']);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      });

      test('passes on a clean tree', () async {
        final r = await run(tree({'pubspec.lock': cleanLock, 'app/pubspec.yaml': 'dependencies:\n  http: ^1.0.0\n'}));
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      });

      for (final name in ['firebase_core', 'firebase_crashlytics', 'google_mobile_ads', 'sentry_flutter', 'bugsnag_flutter', 'mixpanel_flutter', 'posthog_flutter', 'appsflyer_sdk', 'datadog_flutter_plugin', 'onesignal_flutter', 'amplitude_flutter', 'facebook_app_events', 'google_analytics_flutter']) {
        test('fails when pubspec.lock contains $name', () async {
          final r = await run(tree({'pubspec.lock': '$cleanLock  $name:\n    dependency: transitive\n'}));
          expect(r.exitCode, 1, reason: name);
          expect('${r.stderr}', contains('banned dependency'));
        });
      }

      test('fails when a pubspec.yaml declares one, even before pub get', () async {
        final r = await run(tree({'pubspec.lock': cleanLock, 'app/pubspec.yaml': 'dependencies:\n  sentry: ^8.0.0\n'}));
        expect(r.exitCode, 1);
      });

      test('fails on a Maven coordinate for Firebase or Play Services in a Gradle file', () async {
        for (final dep in ['com.google.firebase:firebase-analytics:21.0.0', 'com.google.android.gms:play-services-base:18.0.0', 'io.sentry:sentry-android:7.0.0']) {
          final r = await run(tree({'pubspec.lock': cleanLock, 'app/android/app/build.gradle.kts': 'dependencies {\n    implementation("$dep")\n}\n'}));
          expect(r.exitCode, 1, reason: dep);
        }
      });

      test('fails on a Play Services meta-data entry in a manifest, but a comment naming the ban is fine', () async {
        final bad = await run(tree({'pubspec.lock': cleanLock, 'app/android/AndroidManifest.xml': '<manifest><application><meta-data android:name="com.google.android.gms.version"/></application></manifest>'}));
        expect(bad.exitCode, 1);
        final ok = await run(tree({'pubspec.lock': cleanLock, 'app/android/app/build.gradle.kts': '// no com.google.firebase here\n'}));
        expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
      });

      test('a tree without any pubspec.lock is an error, not a pass', () async {
        final r = await run(tree({'app/pubspec.yaml': 'name: x\n'}));
        expect(r.exitCode, 2);
      });

      test('the CI workflow runs it, and the permission check, on every push', () {
        final ci = File('../.github/workflows/ci.yml').readAsStringSync();
        expect(ci, contains('tool/check_banned_deps.sh'));
        expect(ci, contains('tool/check_permissions.sh'));
        expect(ci, contains('flutter build apk --release --split-per-abi'));
        expect(ci, contains('push:'));
      });
    });
  });
}

class _Hostile {
  @override
  String toString() => throw StateError('toString must never be called: sk-secret');
}
