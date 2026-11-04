import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'move_badge.dart';

/// Win% over the plies, White POV (SPEC F9): a custom painter, no chart
/// library. The line is White's Win% (White advantage up), key moments are
/// dots in their badge colour, the current ply is a vertical cursor. Tap or
/// drag to jump; the screen-reader node is a slider that steps through the
/// plies.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.data,
    required this.ply,
    required this.onSelect,
    this.height = 80,
  });

  final BoardData data;
  final int ply;
  final ValueChanged<int> onSelect;
  final double height;

  /// What the slider announces for position [p]: the full move number and who
  /// moved ("Move 12, Black"), not the half-move count.
  String _valueAt(AppLocalizations l10n, int p) {
    if (p <= 0) return l10n.evalGraphValueStart;
    final before = data.positionBefore(p);
    return l10n.evalGraphValue(before.fullmoves, before.turn == Side.white ? l10n.sideWhite : l10n.sideBlack);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final n = data.plyCount;
    final badgeColors = {for (final l in MoveLabel.values) l: badgeStyleOf(context, l).background};
    return Semantics(
      container: true,
      slider: true,
      label: l10n.evalGraphSemantics,
      value: _valueAt(l10n, ply),
      increasedValue: _valueAt(l10n, (ply + 1).clamp(0, n)),
      decreasedValue: _valueAt(l10n, (ply - 1).clamp(0, n)),
      onIncrease: ply < n ? () => onSelect(ply + 1) : null,
      onDecrease: ply > 0 ? () => onSelect(ply - 1) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            int plyAt(double dx) => n == 0 ? 0 : (dx / width * n).round().clamp(0, n);
            return GestureDetector(
              key: const Key('eval-graph'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onSelect(plyAt(d.localPosition.dx)),
              onHorizontalDragStart: (d) => onSelect(plyAt(d.localPosition.dx)),
              onHorizontalDragUpdate: (d) => onSelect(plyAt(d.localPosition.dx)),
              child: SizedBox(
                height: height,
                width: double.infinity,
                child: CustomPaint(
                  painter: EvalGraphPainter(
                    wins: [for (var p = 0; p <= n; p++) data.whiteWinAt(p)],
                    moments: [for (final m in data.keyMoments) (m.ply, m.label)],
                    current: ply,
                    badgeColors: badgeColors,
                    whiteColor: const Color(0xFFF4F4F4),
                    blackColor: const Color(0xFF262626),
                    lineColor: theme.colorScheme.primary,
                    cursorColor: theme.colorScheme.tertiary,
                    outline: theme.colorScheme.outline,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints [EvalGraph]. Public so tests can compute its geometry.
class EvalGraphPainter extends CustomPainter {
  EvalGraphPainter({
    required this.wins,
    required this.moments,
    required this.current,
    required this.badgeColors,
    required this.whiteColor,
    required this.blackColor,
    required this.lineColor,
    required this.cursorColor,
    required this.outline,
  });

  /// White's Win% per position (index = ply), null = not analysed yet.
  final List<double?> wins;

  /// (ply, label) of every key moment.
  final List<(int, MoveLabel)> moments;
  final int current;
  final Map<MoveLabel, Color> badgeColors;
  final Color whiteColor;
  final Color blackColor;
  final Color lineColor;
  final Color cursorColor;
  final Color outline;

  /// x of position [ply] in a graph of [width].
  static double xOf(int ply, int plies, double width) => plies == 0 ? 0 : ply / plies * width;

  /// y of a White Win% in a graph of [height] (100% = top).
  static double yOf(double win, double height) => (1 - win / 100) * height;

  @override
  void paint(Canvas canvas, Size size) {
    final n = wins.length - 1;
    // Black's half above, White's below the curve.
    canvas.drawRect(Offset.zero & size, Paint()..color = blackColor);
    final area = Path();
    final line = Path();
    var open = false;
    double? lastX;
    for (var p = 0; p <= n; p++) {
      final w = wins[p];
      if (w == null) {
        if (open) {
          area
            ..lineTo(lastX!, size.height)
            ..close();
          open = false;
        }
        continue;
      }
      final x = xOf(p, n, size.width);
      final y = yOf(w, size.height);
      if (!open) {
        area
          ..moveTo(x, size.height)
          ..lineTo(x, y);
        line.moveTo(x, y);
        open = true;
      } else {
        area.lineTo(x, y);
        line.lineTo(x, y);
      }
      lastX = x;
    }
    if (open) {
      area
        ..lineTo(lastX!, size.height)
        ..close();
    }
    canvas.drawPath(area, Paint()..color = whiteColor);
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = outline.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final (ply, label) in moments) {
      final w = wins[ply.clamp(0, n)];
      if (w == null) continue;
      final c = Offset(xOf(ply, n, size.width), yOf(w, size.height));
      canvas.drawCircle(c, 5, Paint()..color = whiteColor);
      canvas.drawCircle(c, 4, Paint()..color = badgeColors[label]!);
    }
    final cx = xOf(current, n, size.width);
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = cursorColor
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(EvalGraphPainter old) =>
      old.current != current ||
      old.wins != wins ||
      old.moments != moments ||
      old.badgeColors != badgeColors ||
      old.lineColor != lineColor;
}
