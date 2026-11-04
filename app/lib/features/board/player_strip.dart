import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_format.dart';

/// Name, rating and the clock at the current move of one player (SPEC F7).
class PlayerStrip extends StatelessWidget {
  const PlayerStrip({
    super.key,
    required this.side,
    required this.name,
    this.elo,
    this.clockMs,
    this.isUser = false,
    this.toMove = false,
  });

  final Side side;
  final String? name;
  final int? elo;

  /// Remaining time after this player's latest move (`[%clk]`), if known.
  final int? clockMs;

  /// The user played this side (SPEC F15).
  final bool isUser;

  /// This player is on the move in the shown position.
  final bool toMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final displayName = name ?? l10n.libraryUnknownPlayer;
    final clock = clockMs == null ? null : formatClock(clockMs!);
    final sideName = side == Side.white ? l10n.sideWhite : l10n.sideBlack;
    final semantics = [
      sideName,
      displayName,
      if (isUser) l10n.playerYou,
      if (elo != null) l10n.playerRatingSemantics(elo!),
      if (clock != null) l10n.playerClockSemantics(clock),
    ].join(', ');
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: side == Side.white ? const Color(0xFFF4F4F4) : const Color(0xFF262626),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(width: 8),
              // A Wrap, not a Row: with large text the name, rating and "You"
              // marker go on a second line instead of overflowing.
              Expanded(
                child: Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayName,
                      key: Key('strip-name-${side.name}'),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (elo != null) Text(l10n.playerRating(elo!), style: theme.textTheme.bodySmall),
                    if (isUser)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l10n.playerYou,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                  ],
                ),
              ),
              if (clock != null)
                Container(
                  key: Key('strip-clock-${side.name}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: toMove ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    clock,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: toMove ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
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
