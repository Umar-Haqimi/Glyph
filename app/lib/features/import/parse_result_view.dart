import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../library/game_text.dart';
import 'pgn_issue_text.dart';

/// What the import screens show for a [PgnParseResult]: the "N games found"
/// line, skipped-game reasons or the error, and (for more than one game) the
/// picker. Pass `result: null` for empty input.
class ParseResultView extends StatelessWidget {
  const ParseResultView({
    super.key,
    required this.result,
    required this.selected,
    required this.onSelect,
  });

  final PgnParseResult? result;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = result;
    if (r == null) return const SizedBox.shrink();

    if (r is PgnFailed) {
      final more = r.issues.skip(1).take(3);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pgnIssueText(l10n, r.issue),
                    key: const Key('importError'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
            for (final issue in more)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Text(
                  pgnIssueText(l10n, issue, withGame: true),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      );
    }

    final skipped = r is PgnPartial ? r.skipped : const <PgnIssue>[];
    final summary = skipped.isEmpty
        ? l10n.importGamesFound(r.games.length)
        : l10n.importGamesFoundSkipped(r.games.length, skipped.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(summary, key: const Key('importSummary'), style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
        for (final issue in skipped.take(5))
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 4),
            child: Text(
              pgnIssueText(l10n, issue, withGame: true),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        if (r.games.length > 1) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(l10n.importChooseGame, style: theme.textTheme.titleSmall),
          ),
          for (var i = 0; i < r.games.length; i++)
            _GameTile(
              game: r.games[i],
              selected: selected == i,
              onTap: () => onSelect(i),
            ),
        ],
      ],
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game, required this.selected, required this.onTap});

  final Game game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = [
      formatResult(game.result),
      if (game.date != null) formatDate(game.date!),
      l10n.libraryMoveCount((game.plyCount + 1) ~/ 2),
    ].join(' · ');
    return ListTile(
      key: ValueKey('game-${game.sourceIndex}'),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
      title: Text(l10n.libraryGameTitle(
        game.white ?? l10n.libraryUnknownPlayer,
        game.black ?? l10n.libraryUnknownPlayer,
      )),
      subtitle: Text(details),
      onTap: onTap,
    );
  }
}
