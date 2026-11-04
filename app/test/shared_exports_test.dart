import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/platform/shared_exports.dart';

/// The exported PGN (`cache/shared_pgn/`, written by MainActivity.sharePgn) is
/// removed by Dart through the cache directory path_provider reports.
void main() {
  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('glyph_cache'));
  tearDown(() => cache.deleteSync(recursive: true));

  CacheSharedExports exports() => CacheSharedExports(cacheDir: () async => cache);

  test('the folder name is the one MainActivity writes and the FileProvider exposes', () {
    expect(sharedPgnDirName, 'shared_pgn');
    final kotlin = File('android/app/src/main/kotlin/my/umarh/glyph/MainActivity.kt').readAsStringSync();
    expect(kotlin, contains('SHARE_DIR = "shared_pgn"'));
    expect(kotlin, contains('File(cacheDir, SHARE_DIR)'), reason: 'path_provider\'s temporary directory is Context.cacheDir');
    final paths = File('android/app/src/main/res/xml/file_paths.xml');
    if (paths.existsSync()) expect(paths.readAsStringSync(), contains('shared_pgn/'));
  });

  test('clear() deletes the exported files, and only that folder', () async {
    final dir = Directory('${cache.path}/$sharedPgnDirName')..createSync();
    File('${dir.path}/Alice_Bob.pgn').writeAsStringSync('[White "Alice"]\n1. e4 *');
    File('${dir.path}/second.pgn').writeAsStringSync('1. d4 *');
    File('${cache.path}/other_cache_file').writeAsStringSync('keep');
    await exports().clear();
    expect(dir.existsSync() ? dir.listSync() : <FileSystemEntity>[], isEmpty);
    expect(File('${cache.path}/other_cache_file').existsSync(), isTrue);
  });

  test('clear() with no folder is not an error, and can run twice', () async {
    await exports().clear();
    await exports().clear();
    expect(cache.listSync(), isEmpty);
  });
}
