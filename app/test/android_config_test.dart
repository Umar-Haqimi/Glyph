import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_core/glyph_core.dart';

/// The Android side cannot be built in CI without an SDK (docs/PROGRESS.md);
/// these tests pin what can be checked as text: no new permission, the intent
/// filters of SPEC F2, the FileProvider, and the byte cap of the native reader.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final activity = File('android/app/src/main/kotlin/my/umarh/glyph/MainActivity.kt').readAsStringSync();

  test('the main manifest requests exactly INTERNET (share and export add no permission)', () {
    final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"').allMatches(manifest).map((m) => m.group(1)).toList();
    expect(permissions, ['android.permission.INTERNET']);
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA')));
    expect(manifest, contains('android:allowBackup="false"'));
  });

  List<String> filters() => RegExp(r'<intent-filter>(.*?)</intent-filter>', dotAll: true).allMatches(manifest).map((m) => m.group(1)!).toList();

  test('intent filters: launcher, text/plain share, PGN file share, Open with by mime type and by *.pgn name', () {
    final all = filters();
    expect(all.length, 5);
    expect(all.where((f) => f.contains('android.intent.action.MAIN')).length, 1);
    final send = all.where((f) => f.contains('android.intent.action.SEND')).toList();
    expect(send.length, 2);
    expect(send.any((f) => f.contains('android:mimeType="text/plain"')), isTrue);
    expect(send.any((f) => f.contains('application/x-chess-pgn') && f.contains('application/vnd.chess-pgn') && f.contains('text/x-chess-pgn')), isTrue);
    final view = all.where((f) => f.contains('android.intent.action.VIEW')).toList();
    expect(view.length, 2);
    for (final f in view) {
      expect(f.contains('android.intent.category.DEFAULT'), isTrue);
      expect(f.contains('android:scheme="content"') && f.contains('android:scheme="file"'), isTrue);
    }
    expect(view.any((f) => f.contains('application/x-chess-pgn')), isTrue);
    final byName = view.firstWhere((f) => f.contains('pathPattern'));
    expect(byName, contains('android:mimeType="*/*"'));
    expect(RegExp('pathPattern').allMatches(byName).length, 3, reason: 'a.pgn, a.b.pgn, a.b.c.pgn');
    expect(byName, isNot(contains('pathSuffix')), reason: 'API 31+ only');
    for (final f in all.where((f) => !f.contains('MAIN'))) {
      expect(f, contains('android.intent.category.DEFAULT'));
    }
  });

  test('the activity stays singleTop and exported (a share while the app runs arrives in onNewIntent)', () {
    expect(manifest, contains('android:launchMode="singleTop"'));
    expect(manifest, contains('android:exported="true"'));
    expect(activity, contains('override fun onNewIntent'));
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
}
