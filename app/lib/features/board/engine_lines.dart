import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';

/// One engine line prepared for display: score, depth and the moves in SAN.
class EngineLineView {
  const EngineLineView({required this.rank, required this.score, required this.depth, required this.moves});

  final int rank;
  final String score;
  final int depth;

  /// `12. Nf3 Nc6 13. d4` (Chess960 castling converted by dartchess: a
  /// king-takes-rook UCI comes out as `O-O`).
  final String moves;
}

/// The stored lines of position [ply] as SAN (SPEC F8), at most [maxLines].
List<EngineLineView> engineLineViews(BoardData data, int ply, {int maxLines = 2, int maxMoves = 8}) {
  final position = data.positionAt(ply);
  final out = <EngineLineView>[];
  for (final line in data.linesAt(ply) ?? const <EngineLine>[]) {
    if (line.rank > maxLines) continue;
    out.add(EngineLineView(
      rank: line.rank,
      score: formatScore(line.score),
      depth: line.depth,
      moves: formatMoveSequence(position, pvToSan(position, line.pv, maxMoves: maxMoves)),
    ));
  }
  out.sort((a, b) => a.rank.compareTo(b.rank));
  return out;
}

/// Collapsible "Engine lines" row (SPEC section 4): the top two lines of the
/// current position from the stored analysis.
class EngineLinesPanel extends StatelessWidget {
  const EngineLinesPanel({
    super.key,
    required this.data,
    required this.ply,
    required this.expanded,
    required this.onToggle,
  });

  final BoardData data;
  final int ply;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final views = engineLineViews(data, ply);
    final terminal = data.terminalAt(ply);

    Widget body;
    if (terminal != null) {
      body = Text(
        switch (terminal.kind) {
          TerminalKind.checkmate => l10n.engineLinesCheckmate,
          TerminalKind.stalemate => l10n.engineLinesStalemate,
          TerminalKind.insufficientMaterial => l10n.engineLinesInsufficient,
        },
        key: const Key('engine-lines-terminal'),
      );
    } else if (views.isEmpty) {
      body = Text(l10n.engineLinesWaiting, key: const Key('engine-lines-waiting'));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final v in views)
            Semantics(
              container: true,
              label: l10n.engineLineSemantics(v.rank, v.score, v.depth, v.moves),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: Key('engine-line-score-${v.rank}'),
                        constraints: const BoxConstraints(minWidth: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          v.score,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          v.moves,
                          key: Key('engine-line-moves-${v.rank}'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.engineLineDepth(v.depth), style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.engineLinesTitle, style: theme.textTheme.titleSmall)),
              IconButton(
                key: const Key('engine-lines-toggle'),
                tooltip: expanded ? l10n.engineLinesHide : l10n.engineLinesShow,
                onPressed: onToggle,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
          if (expanded) body,
        ],
      ),
    );
  }
}
