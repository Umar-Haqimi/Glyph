import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';
import 'move_badge.dart';
import 'spoken_move.dart';

/// Opens the Key moments sheet (SPEC F9): every Brilliant, Great, Miss,
/// Mistake and Blunder, per side. Returns the ply the user picked, or null.
Future<int?> showKeyMomentsSheet(BuildContext context, BoardData data) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => KeyMomentsSheet(data: data),
  );
}

class KeyMomentsSheet extends StatelessWidget {
  const KeyMomentsSheet({super.key, required this.data});

  final BoardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final moments = data.keyMoments;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          key: const Key('key-moments-list'),
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(l10n.boardKeyMoments, style: theme.textTheme.titleLarge),
            ),
            if (moments.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  data.analysisComplete ? l10n.keyMomentsNone : l10n.keyMomentsPending,
                  key: const Key('key-moments-empty'),
                ),
              )
            else
              for (final side in Side.values) ..._section(context, l10n, theme, side, KeyMoments.ofSide(moments, side)),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(BuildContext context, AppLocalizations l10n, ThemeData theme, Side side, List<KeyMoment> moments) {
    if (moments.isEmpty) return const [];
    final name = side == Side.white ? data.record.white : data.record.black;
    final you = data.userSide == side;
    final sideName = side == Side.white ? l10n.sideWhite : l10n.sideBlack;
    final header = name == null
        ? (you ? l10n.keyMomentsHeaderSideOnlyYou(sideName) : l10n.keyMomentsHeaderSideOnly(sideName))
        : (you ? l10n.keyMomentsHeaderYou(sideName, name) : l10n.keyMomentsHeader(sideName, name));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(header, style: theme.textTheme.titleSmall),
      ),
      for (final m in moments) _tile(context, l10n, theme, m),
    ];
  }

  Widget _tile(BuildContext context, AppLocalizations l10n, ThemeData theme, KeyMoment m) {
    final before = data.positionBefore(m.ply);
    final san = data.game.plies[m.ply - 1].san;
    final move = formatMove(before, san);
    final name = labelName(l10n, m.label);
    // White's point of view like the gauge, the graph and the engine lines;
    // the stored values are the mover's.
    int? whitePov(double? win) => win == null ? null : (m.side == Side.white ? win : 100 - win).round();
    final from = whitePov(m.winBefore);
    final to = whitePov(m.winAfter);
    final change = from == null || to == null ? null : l10n.keyMomentWinChance(from, to);
    final spoken = l10n.moveListItemSemantics(spokenMove(l10n, before, san), name);
    return Semantics(
      button: true,
      label: change == null ? spoken : l10n.keyMomentSemantics(spoken, change),
      // One node that carries the tap action for TalkBack; the tile's own
      // semantics are excluded so the row is not read twice.
      onTap: () => Navigator.of(context).pop(m.ply),
      excludeSemantics: true,
      child: ListTile(
        key: Key('key-moment-${m.ply}'),
        minTileHeight: 56,
        leading: MoveBadge(label: m.label, size: 32, excludeSemantics: true),
        title: Text(move),
        subtitle: Text(change == null ? name : l10n.keyMomentSubtitle(name, change)),
        onTap: () => Navigator.of(context).pop(m.ply),
      ),
    );
  }
}
