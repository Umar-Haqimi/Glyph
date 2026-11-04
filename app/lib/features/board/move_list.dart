import 'dart:math' as math;

import 'package:glyph_core/glyph_core.dart' show MoveLabel;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';
import 'move_badge.dart';
import 'spoken_move.dart';

/// The horizontally scrolling move list (SPEC section 4): one chip per ply
/// (`12. Nf3`, `12… Nf6`) with its badge; the current move is centred.
///
/// Lazy: a `ListView.builder` with one fixed extent per chip (wide enough for
/// the longest move of the game at the current text scale), so only the
/// handful of visible chips exist and "centre ply n" is plain arithmetic, no
/// per-chip `GlobalKey`. A navigation step rebuilds only the visible chips.
class MoveList extends StatefulWidget {
  const MoveList({
    super.key,
    required this.data,
    required this.ply,
    required this.onSelect,
  });

  final BoardData data;
  final int ply;
  final ValueChanged<int> onSelect;

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  static const double _padding = 12;
  static const double _gap = 4;
  static const double _badge = 18;
  static const double _chipPadding = 10;

  final ScrollController _controller = ScrollController();

  /// The longest `12. Nf3`-style text of the game (by characters) and the
  /// extent measured for it; both only change with the game, text scale and
  /// theme.
  String? _longest;
  Object? _longestFor;
  double _extent = 96;
  Object? _extentKey;

  @override
  void initState() {
    super.initState();
    _centre(animate: false);
  }

  @override
  void didUpdateWidget(MoveList old) {
    super.didUpdateWidget(old);
    if (old.ply != widget.ply) {
      _centre(animate: (old.ply - widget.ply).abs() <= 1);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scroll offset that puts chip [ply] in the middle of the viewport (the
  /// start position, ply 0, is the left edge).
  double _offsetFor(int ply, double viewport) {
    if (ply <= 0) return 0;
    final centre = _padding + (ply - 1) * _extent + _extent / 2;
    return centre - viewport / 2;
  }

  void _centre({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final target = _offsetFor(
        widget.ply,
        position.viewportDimension,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (animate) {
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        _controller.jumpTo(target);
      }
    });
  }

  /// Width of one chip slot: the longest move text (bold, the selected
  /// weight) at the current text scale, plus badge and paddings.
  double _measureExtent(BuildContext context, ThemeData theme) {
    final data = widget.data;
    if (!identical(_longestFor, data.game)) {
      _longestFor = data.game;
      String? best;
      for (var ply = 1; ply <= data.plyCount; ply++) {
        final text = formatMove(
          data.positionBefore(ply),
          data.game.plies[ply - 1].san,
        );
        if (best == null || text.length > best.length) best = text;
      }
      _longest = best;
    }
    final scaler = MediaQuery.textScalerOf(context);
    final key = (_longestFor, _longest, scaler, theme.textTheme.labelLarge);
    if (_extentKey != key) {
      _extentKey = key;
      final painter = TextPainter(
        text: TextSpan(
          text: _longest ?? '',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      // chip = padding + text + gap + badge + padding; 4 dp of slot margin.
      _extent = math
          .max(72, painter.width + _chipPadding * 2 + _gap + _badge + 4)
          .ceilToDouble();
      painter.dispose();
    }
    return _extent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final data = widget.data;
    final extent = _measureExtent(context, theme);
    return Semantics(
      container: true,
      label: l10n.moveListSemantics,
      child: SizedBox(
        height: 56,
        child: ListView.builder(
          key: const Key('move-list'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: _padding,
            vertical: 4,
          ),
          itemExtent: extent,
          itemCount: data.plyCount,
          itemBuilder: (context, index) {
            final ply = index + 1;
            return _MoveChip(
              key: ValueKey(ply),
              ply: ply,
              selected: ply == widget.ply,
              label: data.moveAt(ply)?.label,
              text: formatMove(
                data.positionBefore(ply),
                data.game.plies[ply - 1].san,
              ),
              spoken: spokenMove(
                l10n,
                data.positionBefore(ply),
                data.game.plies[ply - 1].san,
              ),
              onSelect: widget.onSelect,
            );
          },
        ),
      ),
    );
  }
}

class _MoveChip extends StatefulWidget {
  const _MoveChip({
    super.key,
    required this.ply,
    required this.selected,
    required this.label,
    required this.text,
    required this.spoken,
    required this.onSelect,
  });

  final int ply;
  final bool selected;
  final MoveLabel? label;
  final String text;
  final String spoken;
  final ValueChanged<int> onSelect;

  @override
  State<_MoveChip> createState() => _MoveChipState();
}

class _MoveChipState extends State<_MoveChip> {
  /// The badge appeared while this chip was on screen (the analysis filled it
  /// in): pop it in. A chip that is built with its badge already there (it
  /// scrolled into view) does not animate.
  bool _popBadge = false;

  @override
  void didUpdateWidget(_MoveChip old) {
    super.didUpdateWidget(old);
    if (old.label == null && widget.label != null) _popBadge = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = widget.label;
    final selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // One node with the tap action: the chip's own children are excluded so
      // the screen reader reads a single "button" and TalkBack can activate it.
      child: Semantics(
        button: true,
        selected: selected,
        label: label == null
            ? widget.spoken
            : l10n.moveListItemSemantics(widget.spoken, labelName(l10n, label)),
        onTap: () => widget.onSelect(widget.ply),
        excludeSemantics: true,
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: Key('move-chip-${widget.ply}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.onSelect(widget.ply),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _MoveListState._chipPadding,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.text,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                          fontWeight: selected ? FontWeight.w800 : null,
                        ),
                      ),
                      if (label != null) ...[
                        const SizedBox(width: _MoveListState._gap),
                        PopIn(
                          play: _popBadge,
                          child: MoveBadge(
                            label: label,
                            size: _MoveListState._badge,
                            excludeSemantics: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
