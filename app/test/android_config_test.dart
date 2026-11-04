import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_core/glyph_core.dart';

/// The Android side cannot be built in CI without an SDK (docs/PROGRESS.md);
/// these tests pin what can be checked as text: no new permission, the intent
/// filters of SPEC F2, the FileProvider, and the byte cap of the native reader.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final activity = File('android/app/src/main/kotlin/my/umarh/glyph/MainActivity.kt').readAsStringSync();
  final intakeActivity = File('android/app/src/main/kotlin/my/umarh/glyph/ShareIntakeActivity.kt').readAsStringSync();

  String activityBlock(String name) =>
      RegExp('<activity\\s[^>]*android:name="\\.$name"[^>]*>.*?</activity>', dotAll: true).firstMatch(manifest)!.group(0)!;
  final mainBlock = activityBlock('MainActivity');
  final intakeBlock = activityBlock('ShareIntakeActivity');

  test('the main manifest requests exactly INTERNET (share and export add no permission)', () {
    final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"').allMatches(manifest).map((m) => m.group(1)).toList();
    expect(permissions, ['android.permission.INTERNET']);
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA')));
    expect(manifest, contains('android:allowBackup="false"'));
  });

  List<String> filtersOf(String block) =>
      RegExp(r'<intent-filter>(.*?)</intent-filter>', dotAll: true).allMatches(block).map((m) => m.group(1)!).toList();

  test('MainActivity has the launcher filter only; every SEND / VIEW filter belongs to ShareIntakeActivity', () {
    final main = filtersOf(mainBlock);
    expect(main.length, 1);
    expect(main.single, contains('android.intent.action.MAIN'));
    expect(main.single, contains('android.intent.category.LAUNCHER'));
    expect(manifest.split('<intent-filter>').length - 1, 5);
  });

  test('intake filters: text/plain share, PGN file share, Open with by mime type and by *.pgn name; content scheme only', () {
    final all = filtersOf(intakeBlock);
    expect(all.length, 4);
    final send = all.where((f) => f.contains('android.intent.action.SEND')).toList();
    expect(send.length, 2);
    expect(send.any((f) => f.contains('android:mimeType="text/plain"')), isTrue);
    expect(send.any((f) => f.contains('application/x-chess-pgn') && f.contains('application/vnd.chess-pgn') && f.contains('text/x-chess-pgn')), isTrue);
    final view = all.where((f) => f.contains('android.intent.action.VIEW')).toList();
    expect(view.length, 2);
    for (final f in view) {
      expect(f.contains('android.intent.category.DEFAULT'), isTrue);
      expect(f.contains('android:scheme="content"'), isTrue);
      expect(f.contains('android:scheme="file"'), isFalse, reason: 'file: URIs are not accepted');
    }
    expect(manifest, isNot(contains('android:scheme="file"')));
    expect(view.any((f) => f.contains('application/x-chess-pgn')), isTrue);
    final byName = view.firstWhere((f) => f.contains('pathPattern'));
    expect(byName, contains('android:mimeType="*/*"'));
    expect(RegExp('pathPattern').allMatches(byName).length, 3, reason: 'a.pgn, a.b.pgn, a.b.c.pgn');
    expect(byName, isNot(contains('pathSuffix')), reason: 'API 31+ only');
    for (final f in all) {
      expect(f, contains('android.intent.category.DEFAULT'));
    }
  });

  test('ShareIntakeActivity is a UI-less, history-less forwarder; MainActivity is singleTask in the app task', () {
    expect(intakeBlock, contains('android:exported="true"'));
    expect(intakeBlock, contains('Theme.NoDisplay'));
    expect(intakeBlock, contains('android:excludeFromRecents="true"'));
    expect(intakeBlock, contains('android:noHistory="true"'));
    expect(intakeActivity, contains('class ShareIntakeActivity : Activity()'));
    expect(intakeActivity, isNot(contains('FlutterActivity')), reason: 'no second engine');
    expect(intakeActivity, contains('FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP'));
    expect(intakeActivity, contains('FLAG_GRANT_READ_URI_PERMISSION'));
    expect(intakeActivity, contains('finish()'));
    expect(mainBlock, contains('android:launchMode="singleTask"'));
    expect(mainBlock, contains('android:exported="true"'), reason: 'the launcher needs it');
    expect(manifest, isNot(contains('android:taskAffinity')));
    expect(manifest, isNot(contains('singleTop')));
    expect(activity, contains('override fun onNewIntent'));
  });

  test('MainActivity acts only on intents from the intake activity, never after process-death restore', () {
    expect(activity, contains('IntakeGate.EXTRA_TOKEN'));
    expect(activity, contains('!= IntakeGate.token'));
    expect(intakeActivity, contains('UUID.randomUUID()'));
    expect(activity, contains('restored = savedInstanceState != null'));
    expect(activity, contains('if (!restored) handleIntent(intent)'));
  });

  test('intent data never becomes a Flutter route', () {
    expect(mainBlock, contains('android:name="flutter_deeplinking_enabled"'));
    expect(RegExp(r'flutter_deeplinking_enabled"\s*android:value="false"').hasMatch(mainBlock), isTrue);
  });

  test('only content: URIs are read, and never one served by Glyph itself', () {
    expect(intakeActivity, contains('uri.scheme != "content"'));
    expect(intakeActivity, contains('authority == own || authority.startsWith("\$own.")'));
    expect(activity, contains('IntakeGate.isAcceptable(uri, packageName)'));
    expect(intakeActivity, contains('IntakeGate.isAcceptable(uri, packageName)'));
    expect(activity + intakeActivity, isNot(contains('scheme != "content" && scheme != "file"')));
  });

  test('a stalled provider is cut off by a watchdog and never blocks a later share', () {
    expect(activity, contains('READ_TIMEOUT_MS = 15_000L'));
    expect(activity, contains('"kind" to "timeout"'));
    expect(activity, contains('"kind" to "reading"'));
    expect(activity, contains('thread(name = "glyph-intake-read", isDaemon = true)'));
    expect(activity, isNot(contains('Executors')));
    expect(activity, contains('open.get()?.close()'));
  });

  test('text extras are read as CharSequence; export excludes Glyph and keeps big PGNs out of EXTRA_TEXT', () {
    expect(activity, contains('getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()'));
    expect(activity, isNot(contains('getStringExtra(Intent.EXTRA_TEXT)')));
    expect(activity, contains('Intent.EXTRA_EXCLUDE_COMPONENTS'));
    expect(activity, contains('ComponentName(this, ShareIntakeActivity::class.java)'));
    expect(activity, contains('MAX_EXTRA_TEXT_BYTES = 100 * 1024'));
    expect(activity, contains('text.toByteArray(Charsets.UTF_8).size <= MAX_EXTRA_TEXT_BYTES'));
  });

  test('the FileProvider is private, grants per URI, and serves one cache folder only', () {
    final provider = RegExp(r'<provider.*?</provider>', dotAll: true).firstMatch(manifest)!.group(0)!;
    expect(provider, contains('androidx.core.content.FileProvider'));
    expect(provider, contains('android:exported="false"'));
    expect(provider, contains('android:grantUriPermissions="true"'));
    expect(provider, contains(r'${applicationId}.fileprovider'));
    final paths = File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    expect(RegExp(r'<(cache-path|files-path|external[a-z-]*|root-path)\b').allMatches(paths).map((m) => m.group(1)), ['cache-path']);
    expect(paths, contains('path="shared_pgn/"'));
  });

  test('MainActivity reads at most Limits.maxPgnBytes, never touches shared storage and never writes intake data', () {
    expect(Limits.maxPgnBytes, 2 * 1024 * 1024);
    expect(activity, contains('private const val MAX_BYTES = 2 * 1024 * 1024'));
    expect(activity, contains('if (total > MAX_BYTES)'));
    expect(activity, contains('LAUNCHED_FROM_HISTORY'));
    expect(activity, isNot(contains('getExternalStorage')));
    expect(activity, isNot(contains('getExternalFilesDir')));
    expect(activity, isNot(contains('MediaStore')));
    // The only file written is the exported PGN in the cache folder.
    expect(RegExp(r'\.writeText\(|FileOutputStream|openOutputStream').allMatches(activity).length, 1);
    expect(activity, contains('File(cacheDir, SHARE_DIR)'));
  });

  test('the channel names match the Dart side', () {
    expect(activity, contains('"my.umarh.glyph/intake"'));
    expect(activity, contains('"my.umarh.glyph/export"'));
    final dart = File('lib/platform/share_intake.dart').readAsStringSync() + File('lib/platform/pgn_share_service.dart').readAsStringSync();
    expect(dart, contains("'my.umarh.glyph/intake'"));
    expect(dart, contains("'my.umarh.glyph/export'"));
    for (final method in ['ready', 'shared', 'sharePgn']) {
      expect(activity.contains('"$method"') || dart.contains("'$method'"), isTrue, reason: method);
    }
  });

  test('the network security config is unchanged: lichess and chess.com are https, nothing to add', () {
    final config = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    expect(config, contains('cleartextTrafficPermitted="true"'));
    expect(config, isNot(contains('<domain')));
  });

  group('release hardening (SPEC 6, M8)', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();

    test('R8 minification and resource shrinking are on for the release build type, with the Glyph rules', () {
      final release = RegExp(r'release \{.*?\n        \}', dotAll: true).firstMatch(gradle)!.group(0)!;
      expect(release, contains('isMinifyEnabled = true'));
      expect(release, contains('isShrinkResources = true'));
      expect(release, contains('proguard-android-optimize.txt'));
      expect(release, contains('"proguard-rules.pro"'));
      expect(release, isNot(contains('isDebuggable = true')));
    });

    test('signing comes from key.properties or the four GLYPH_ environment variables; nothing is committed', () {
      for (final name in ['GLYPH_KEYSTORE_FILE', 'GLYPH_KEYSTORE_PASSWORD', 'GLYPH_KEY_ALIAS', 'GLYPH_KEY_PASSWORD']) {
        expect(gradle, contains('"$name"'), reason: name);
      }
      expect(gradle, contains('System.getenv(envName)'));
      expect(gradle, contains('rootProject.file("key.properties")'));
      // No literal password or store path in the build file.
      expect(gradle, isNot(matches(RegExp(r'storePassword\s*=\s*"'))));
      expect(gradle, isNot(matches(RegExp(r'keyPassword\s*=\s*"'))));
      final ignore = File('../.gitignore').readAsStringSync();
      for (final pattern in ['key.properties', '*.jks', '*.keystore']) {
        expect(ignore, contains(pattern), reason: '.gitignore must cover $pattern');
      }
      final tracked = Process.runSync('git', ['ls-files'], workingDirectory: '..').stdout as String;
      expect(RegExp(r'(^|/)key\.properties$|\.jks$|\.keystore$', multiLine: true).hasMatch(tracked), isFalse, reason: 'a keystore or key.properties is tracked');
    });

    test('an empty signing value counts as missing, and storeFile is documented as relative to android/', () {
      expect(gradle, contains('takeIf { it.isNotBlank() }'));
      expect(RegExp(r'getProperty\(propertyName\)\?\.takeIf \{ it\.isNotBlank\(\) \}').hasMatch(gradle), isTrue, reason: 'key.properties values');
      expect(RegExp(r'System\.getenv\(envName\)\)\s*\?\.takeIf \{ it\.isNotBlank\(\) \}').hasMatch(gradle), isTrue, reason: 'environment values');
      expect(gradle, contains('relative to the android/ directory'));
    });

    group('tool/check_signing.sh (apksigner)', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('signing'));
      tearDown(() => dir.deleteSync(recursive: true));

      /// A stand-in `apksigner` that prints [dn] as the signer (or fails).
      String fakeApksigner(String dn, {int exit = 0}) {
        final f = File('${dir.path}/apksigner')
          ..writeAsStringSync('#!/usr/bin/env bash\necho "Signer #1 certificate DN: $dn"\nexit $exit\n');
        Process.runSync('chmod', ['+x', f.path]);
        return f.path;
      }

      ProcessResult run(String signer, {required bool require}) {
        File('${dir.path}/app-x-release.apk').writeAsStringSync('apk');
        return Process.runSync(
          'bash',
          ['../tool/check_signing.sh', '${dir.path}/app-x-release.apk'],
          environment: {'APKSIGNER': signer, 'GLYPH_REQUIRE_SIGNING': require ? '1' : '0'},
        );
      }

      test('a debug-signed APK fails when signing is required, and only warns otherwise', () {
        final signer = fakeApksigner('C=US, O=Android, CN=Android Debug');
        final strict = run(signer, require: true);
        expect(strict.exitCode, isNot(0));
        expect(strict.stderr, contains('debug key'));
        final lax = run(signer, require: false);
        expect(lax.exitCode, 0);
        expect(lax.stderr, contains('WARN'));
      });

      test('an APK signed with another key passes; an APK apksigner rejects fails', () {
        expect(run(fakeApksigner('CN=Glyph release, O=Umar'), require: true).exitCode, 0);
        expect(run(fakeApksigner('CN=Glyph release', exit: 1), require: true).exitCode, isNot(0));
      });

      test('the release script runs it, after the build and before the permission check', () {
        final script = File('../tool/build_release.sh').readAsStringSync();
        expect(script, contains('tool/check_signing.sh'));
        expect(script.indexOf('check_signing.sh'), lessThan(script.indexOf('check_permissions.sh')));
        expect(script.indexOf('flutter build apk'), lessThan(script.indexOf('check_signing.sh')));
      });
    });

    test('GLYPH_REQUIRE_SIGNING=1 makes a release build without a keystore fail, and the release script sets it', () {
      expect(gradle, contains('GLYPH_REQUIRE_SIGNING'));
      expect(gradle, contains('throw GradleException'));
      final script = File('../tool/build_release.sh').readAsStringSync();
      expect(script, contains('GLYPH_REQUIRE_SIGNING=1'));
      expect(script, contains('--split-debug-info=build/symbols'));
      expect(script, contains('flutter build apk --release --split-per-abi'));
      expect(script, contains('check_permissions.sh'));
    });

    test('the rules file documents the plugin audit, keeps stack traces mappable and silences only the Play Core warning', () {
      expect(rules, contains('flutter_secure_storage'));
      expect(rules, contains('file_picker'));
      expect(rules, contains('multistockfish'));
      expect(rules, contains('sqlite3'));
      expect(rules, contains('-keepattributes SourceFile,LineNumberTable'));
      final active = rules.split('\n').where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#')).toList();
      expect(active.where((l) => l.startsWith('-dontwarn')).toList(), ['-dontwarn com.google.android.play.core.**']);
      expect(active.where((l) => l.startsWith('-dontobfuscate') || l.startsWith('-dontshrink') || l.startsWith('-dontoptimize')), isEmpty);
    });

    test('Dart debug symbols never end up in the APK: the symbols directory is a build output', () {
      expect(File('../.gitignore').readAsStringSync(), contains('build/'));
    });
  });
}
