import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../library/library_controller.dart';

/// Saves a parsed [Game] to the library: names the opening from the book and
/// detects the user's side from the configured account names.
class ImportService {
  ImportService(this._ref);

  final Ref _ref;

  /// [userSide] is a side that is already known (an online import knows which
  /// account it fetched); without it the side comes from the configured
  /// account names (SPEC F15). Detection runs once, at import: changing a
  /// name later does not touch games already in the library.
  Future<SaveResult> save(Game game, GameSource source, {String? sourceId, Side? userSide}) async {
    OpeningBook? book;
    try {
      book = await _ref.read(openingBookProvider.future);
    } catch (_) {
      book = null;
    }
    final settings = _ref.read(settingsRepositoryProvider);
    final side = userSide ??
        detectUserSide(
          game,
          lichessUsername: await settings.get(SettingsKeys.lichessUsername),
          chessComUsername: await settings.get(SettingsKeys.chessComUsername),
        );
    final result = await _ref.read(gameRepositoryProvider).save(
          NewGame.fromGame(
            game,
            source: source,
            sourceId: sourceId,
            importedAt: _ref.read(nowMsProvider)(),
            book: book?.annotate(game),
            userSide: side,
          ),
        );
    await _ref.read(libraryProvider.notifier).refresh();
    return result;
  }
}

final importServiceProvider = Provider<ImportService>(ImportService.new);
