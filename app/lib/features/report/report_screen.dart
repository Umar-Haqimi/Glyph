import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../board/board_data.dart';
import '../board/eval_graph.dart';
import '../board/move_badge.dart';

/// Report card (SPEC F6 / section 4, screen 4): accuracy per player, label
/// counts per side, the opening and the eval graph. Tapping the graph returns
/// the picked ply to the board. The game summary block belongs to M6.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, this.gameId, this.initialPly = 0});

  final int? gameId;

  /// The ply the board shows when the report opens; "Show on board" without
  /// touching the graph hands it back unchanged.
  final int initialPly;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late int _ply = widget.initialPly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.gameId;
    final data = id == null ? null : ref.watch(boardDataProvider(id)).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: data == null
          ? Center(
              child: id == null || !ref.watch(boardDataProvider(id)).isLoading
                  ? Text(l10n.boardUnavailable)
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ReportCard(data: data),
                const SizedBox(height: 16),
                Text(l10n.reportGraphTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                EvalGraph(
                  data: data,
                  ply: _ply,
                  height: 120,
                  onSelect: (p) => setState(() => _ply = p),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    key: const Key('report-show-on-board'),
                    onPressed: () => Navigator.of(context).pop(_ply),
                    child: Text(l10n.reportShowOnBoard),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Accuracy rings, the label table and the opening of one game.
class ReportCard extends StatelessWidget {
  const ReportCard({super.key, required this.data});

  final BoardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final opening = data.record.openingName ?? data.book.opening?.name;
    final eco = data.record.eco ?? data.book.opening?.eco;
    final openingText = opening == null ? l10n.reportOpeningUnknown : eco == null ? opening : l10n.reportOpeningEco(eco, opening);
    return Card(
      key: const Key('report-card'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final side in Side.values)
                  Expanded(child: _PlayerAccuracy(data: data, side: side)),
              ],
            ),
            if (!data.analysisComplete) ...[
              const SizedBox(height: 8),
              Text(l10n.reportAccuracyPending, key: const Key('report-pending'), style: theme.textTheme.bodySmall),
            ],
            const Divider(height: 24),
            Text(l10n.reportOpening, style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(openingText, key: const Key('report-opening')),
            const Divider(height: 24),
            Text(l10n.reportMoves, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            _CountTable(data: data),
          ],
        ),
      ),
    );
  }
}

class _PlayerAccuracy extends StatelessWidget {
  const _PlayerAccuracy({required this.data, required this.side});

  final BoardData data;
  final Side side;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accuracy = side == Side.white ? data.record.whiteAccuracy : data.record.blackAccuracy;
    // Rounded like lichess (`Accuracy.display`, floor(x + 0.5)).
    final shown = accuracy == null ? null : Accuracy.display(accuracy);
    final name = side == Side.white ? data.record.white : data.record.black;
    final sideName = side == Side.white ? l10n.sideWhite : l10n.sideBlack;
    return Semantics(
      container: true,
      label: shown == null
          ? l10n.reportAccuracySemanticsUnknown(sideName)
          : l10n.reportAccuracySemantics(sideName, shown),
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: shown == null ? 0 : shown / 100,
                      strokeWidth: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Text(
                    shown?.toString() ?? l10n.reportNoValue,
                    key: Key('report-accuracy-${side.name}'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(sideName, style: theme.textTheme.labelLarge),
            Text(
              name ?? l10n.libraryUnknownPlayer,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountTable extends StatelessWidget {
  const _CountTable({required this.data});

  final BoardData data;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final white = data.counts(Side.white);
    final black = data.counts(Side.black);
    Widget cell(Widget child, {Alignment alignment = Alignment.centerRight}) => Container(
          constraints: const BoxConstraints(minHeight: 40),
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        );
    Widget count(MoveLabel label, Side side, int n) => cell(
          Text(
            n.toString(),
            key: Key('report-count-${label.name}-${side.name}'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: n == 0 ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
              fontWeight: n == 0 ? null : FontWeight.w700,
            ),
          ),
        );
    return Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FixedColumnWidth(72), 2: FixedColumnWidth(72)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            cell(const SizedBox.shrink()),
            cell(Text(l10n.sideWhite, style: theme.textTheme.labelMedium)),
            cell(Text(l10n.sideBlack, style: theme.textTheme.labelMedium)),
          ],
        ),
        for (final label in MoveLabel.values)
          TableRow(
            children: [
              cell(
                Row(
                  children: [
                    MoveBadge(label: label, size: 22, excludeSemantics: true),
                    const SizedBox(width: 8),
                    Flexible(child: Text(labelName(l10n, label))),
                  ],
                ),
                alignment: Alignment.centerLeft,
              ),
              count(label, Side.white, white[label]!),
              count(label, Side.black, black[label]!),
            ],
          ),
      ],
    );
  }
}
