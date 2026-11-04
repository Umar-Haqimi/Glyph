import 'package:glyph_core/glyph_core.dart';

import '../../l10n/app_localizations.dart';

/// Localised text for a [PgnIssue]. Illegal-move messages always name the game;
/// pass [withGame] to prefix the other game-specific ones (skipped-game lists).
String pgnIssueText(AppLocalizations l10n, PgnIssue issue, {bool withGame = false}) {
  final game = issue.gameIndex;
  final text = switch (issue.kind) {
    PgnIssueKind.tooLarge => l10n.importErrorTooLarge,
    PgnIssueKind.noGames => l10n.importErrorNoGames,
    PgnIssueKind.illegalMove => l10n.importErrorIllegalMove(
        game ?? 1,
        '${issue.moveNumber}${issue.isBlackMove ? '...' : ''}',
        issue.san ?? '',
      ),
    PgnIssueKind.unsupportedVariant => l10n.importErrorUnsupportedVariant(issue.variant ?? ''),
    PgnIssueKind.invalidFen => l10n.importErrorInvalidFen,
    PgnIssueKind.tooManyPlies => l10n.importErrorTooManyPlies,
    PgnIssueKind.noMoves => l10n.importErrorNoMoves,
    PgnIssueKind.tooManyGames => l10n.importErrorTooManyGames,
  };
  final named = issue.kind == PgnIssueKind.illegalMove;
  if (withGame && game != null && !named) return l10n.importIssueGame(game, text);
  return text;
}
