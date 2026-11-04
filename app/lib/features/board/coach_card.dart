import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../explain/explain_sheet.dart';
import 'coach.dart';
import 'move_badge.dart';

/// The coach card under the board (SPEC F10): badge, label, the
/// deterministic one-liner and the Explain button (filled tonal for
/// Brilliant / Great / Miss / Inaccuracy / Mistake / Blunder, outlined
/// otherwise; available on every move).
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.line, required this.showExplain, required this.gameId, required this.ply});

  final CoachLine line;

  /// False at the start position (nothing to explain).
  final bool showExplain;

  /// The game and the 1-based ply the Explain button explains.
  final int gameId;
  final int ply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = line.label;
    final moveText = line.moveText;
    final name = label == null ? null : labelName(l10n, label);
    final shownTitle = moveText == null
        ? (name ?? l10n.coachTitleStart)
        : (name == null ? moveText : l10n.coachCardTitle(moveText, name));
    final spokenMove = line.spokenMoveText;
    final spokenTitle = spokenMove == null
        ? shownTitle
        : (name == null ? spokenMove : l10n.coachCardTitle(spokenMove, name));
    final emphasised = label != null && explainEmphasised.contains(label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        key: const Key('coach-card'),
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: l10n.coachSemantics(spokenTitle, line.text),
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (label != null)
                        MoveBadge(label: label, size: 36, excludeSemantics: true)
                      else
                        Icon(Icons.menu_book_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shownTitle, key: const Key('coach-title'), style: theme.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(line.text, key: const Key('coach-text'), style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showExplain)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: emphasised
                        ? FilledButton.tonal(
                            key: const Key('explain-button'),
                            onPressed: () => showExplainSheet(context, gameId: gameId, ply: ply),
                            child: Text(l10n.boardExplain),
                          )
                        : OutlinedButton(
                            key: const Key('explain-button'),
                            onPressed: () => showExplainSheet(context, gameId: gameId, ply: ply),
                            child: Text(l10n.boardExplain),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// True when [label] gets the emphasised (filled tonal) Explain button.
bool isExplainEmphasised(MoveLabel? label) => label != null && explainEmphasised.contains(label);
