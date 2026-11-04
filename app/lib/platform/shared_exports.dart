import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The folder `MainActivity.sharePgn` writes the exported PGN to
/// (`<cache dir>/shared_pgn/`, exposed to the share sheet through a
/// FileProvider). `getTemporaryDirectory()` is the same directory on Android
/// (path_provider_android returns `Context.cacheDir`, verified in 2.3.1), so
/// Dart can remove what Kotlin wrote without another channel call.
const sharedPgnDirName = 'shared_pgn';

/// Removes exported PGN files (they hold a whole game, with its player names).
///
/// When it runs (see `docs/PRIVACY.md` section 3):
/// * at every app start (a file only has to survive until the share sheet's
///   target has read it);
/// * when a game is deleted and by *Delete all data* (an export of a deleted
///   game must not outlive it).
abstract interface class SharedExports {
  /// Deletes every file in the export folder. A missing folder is not an error.
  Future<void> clear();
}

class CacheSharedExports implements SharedExports {
  const CacheSharedExports({this.cacheDir = getTemporaryDirectory});

  /// The app's cache directory (a parameter for tests).
  final Future<Directory> Function() cacheDir;

  @override
  Future<void> clear() async {
    final dir = Directory('${(await cacheDir()).path}/$sharedPgnDirName');
    if (!dir.existsSync()) return;
    await dir.delete(recursive: true);
  }
}

final sharedExportsProvider = Provider<SharedExports>((ref) => const CacheSharedExports());
