import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import 'models.dart';
import 'repositories.dart';

/// Repositories are provided by `main()` (SQLite) or by tests (in-memory
/// fakes); reading one that was not overridden is a programming error.
final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => throw UnimplementedError('gameRepositoryProvider must be overridden'),
);
final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => throw UnimplementedError('analysisRepositoryProvider must be overridden'),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider must be overridden'),
);

final llmCacheRepositoryProvider = Provider<LlmCacheRepository>(
  (ref) => throw UnimplementedError('llmCacheRepositoryProvider must be overridden'),
);

/// Milliseconds since the epoch. Overridable for tests.
final nowMsProvider = Provider<int Function()>((ref) => () => DateTime.now().millisecondsSinceEpoch);

const openingsAsset = 'assets/openings.tsv';

/// The opening book, decoded in an isolate. A failure to load degrades to an
/// empty book (games just have no Book moves) instead of blocking imports.
final openingBookProvider = FutureProvider<OpeningBook>((ref) async {
  try {
    final tsv = await rootBundle.loadString(openingsAsset);
    return await OpeningBook.parseTsvAsync(tsv);
  } catch (_) {
    return OpeningBook(const {});
  }
});

/// One saved game, for the board screen.
final gameProvider = FutureProvider.family<GameRecord?, int>(
  (ref, id) => ref.watch(gameRepositoryProvider).get(id),
);
