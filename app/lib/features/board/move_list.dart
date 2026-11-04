import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';
import 'move_badge.dart';

/// The horizontally scrolling move list (SPEC section 4): one chip per ply
/// (`12. Nf3`, `12… Nf6`) with its badge; the current move is centred.
class MoveList extends StatefulWidget {
  const MoveList({super.key, required this.data, required this.ply, required this.onSelect});

  final BoardData data;
  final int ply;
  final ValueChanged<int> onSelect;

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  late List<GlobalKey> _keys;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.data.plyCount + 1, (_) => GlobalKey());
    _centre(animate: false);
  }

  @override
  void didUpdateWidget(MoveList old) {
    super.didUpdateWidget(old);
    if (old.ply != widget.ply) _centre(animate: (old.ply - widget.ply).abs() <= 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _centre({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keys[widget.ply.clamp(0, _keys.length - 1)].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animate ? const Duration(milliseconds: 150) : Duration.zero,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final data = widget.data;
    return Semantics(
      container: true,
      label: l10n.moveListSemantics,
      child: SizedBox(
        height: 56,
        child: SingleChildScrollView(
          key: const Key('move-list'),
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              // A zero-width anchor so "start position" can be centred too.
              SizedBox(key: _keys[0], width: 0, height: 1),
              for (var ply = 1; ply <= data.plyCount; ply++) _chip(context, l10n, theme, ply),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, AppLocalizations l10n, ThemeData theme, int ply) {
    final data = widget.data;
    final selected = ply == widget.ply;
    final label = data.moveAt(ply)?.label;
    final move = formatMove(data.positionBefore(ply), data.game.plies[ply - 1].san);
    final scheme = theme.colorScheme;
    return Padding(
      key: _keys[ply],
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: label == null ? move : l10n.moveListItemSemantics(move, labelName(l10n, label)),
        child: ExcludeSemantics(
          child: Material(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: Key('move-chip-$ply'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => widget.onSelect(ply),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        move,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                          fontWeight: selected ? FontWeight.w800 : null,
                        ),
                      ),
                      if (label != null) ...[
                        const SizedBox(width: 4),
                        MoveBadge(label: label, size: 18, excludeSemantics: true),
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
