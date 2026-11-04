import 'dart:math' as math;

import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/badge_colors.dart';

/// The text of the five NAG-style badges; the other labels are drawn.
String? badgeText(MoveLabel label) => switch (label) {
      MoveLabel.brilliant => '!!',
      MoveLabel.great => '!',
      MoveLabel.inaccuracy => '?!',
      MoveLabel.mistake => '?',
      MoveLabel.blunder => '??',
      _ => null,
    };

/// Screen-reader name of a label ("Blunder").
String labelName(AppLocalizations l10n, MoveLabel label) => switch (label) {
      MoveLabel.brilliant => l10n.labelBrilliant,
      MoveLabel.great => l10n.labelGreat,
      MoveLabel.best => l10n.labelBest,
      MoveLabel.excellent => l10n.labelExcellent,
      MoveLabel.good => l10n.labelGood,
      MoveLabel.book => l10n.labelBook,
      MoveLabel.forced => l10n.labelForced,
      MoveLabel.inaccuracy => l10n.labelInaccuracy,
      MoveLabel.mistake => l10n.labelMistake,
      MoveLabel.miss => l10n.labelMiss,
      MoveLabel.blunder => l10n.labelBlunder,
    };

/// The colours of [label] in the current theme (light or dark).
BadgeStyle badgeStyleOf(BuildContext context, MoveLabel label) {
  final theme = Theme.of(context);
  final colors = theme.extension<BadgeColors>() ?? BadgeColors.forBrightness(theme.brightness);
  return colors.of(label);
}

/// Glyph's own move-classification badge (SPEC section 4): a coloured disc
/// with the NAG glyph (`!!`, `!`, `?!`, `?`, `??`) or a small vector mark
/// (star, tick, book, arrow, cross) that is drawn here, not taken from an
/// icon font. Never colour-only; announces its label to screen readers.
class MoveBadge extends StatelessWidget {
  const MoveBadge({super.key, required this.label, this.size = 24, this.outlined = false, this.excludeSemantics = false});

  final MoveLabel label;
  final double size;

  /// A thin ring in the glyph colour, so the badge stands out on any square.
  final bool outlined;

  /// Hides the badge from the semantics tree when the surrounding widget
  /// already announces the label.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final style = badgeStyleOf(context, label);
    final text = badgeText(label);
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.background,
        shape: BoxShape.circle,
        border: outlined ? Border.all(color: style.foreground, width: math.max(1, size / 14)) : null,
      ),
      child: text != null
          ? Padding(
              padding: EdgeInsets.all(size * 0.12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: TextStyle(
                    color: style.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: size * 0.62,
                    height: 1,
                  ),
                ),
              ),
            )
          : CustomPaint(
              size: Size.square(size * 0.62),
              painter: _MarkPainter(label, style.foreground, style.background),
            ),
    );
    if (excludeSemantics) return ExcludeSemantics(child: disc);
    return Semantics(
      label: labelName(AppLocalizations.of(context), label),
      image: true,
      child: ExcludeSemantics(child: disc),
    );
  }
}

/// Paints the non-text marks inside a [MoveBadge].
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.label, this.color, this.background);

  final MoveLabel label;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w * 0.17;
    final fill = Paint()..color = color;

    Path tick() => Path()
      ..moveTo(w * 0.08, w * 0.54)
      ..lineTo(w * 0.38, w * 0.82)
      ..lineTo(w * 0.92, w * 0.18);

    switch (label) {
      case MoveLabel.best:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? w * 0.52 : w * 0.22;
          final a = -math.pi / 2 + i * math.pi / 5;
          final p = Offset(w / 2 + r * math.cos(a), w / 2 + r * math.sin(a) + w * 0.03);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), fill);
      case MoveLabel.excellent:
        // A tick cut out of a solid disc.
        canvas.drawCircle(Offset(w / 2, w / 2), w * 0.52, fill);
        canvas.drawPath(
          tick(),
          Paint()
            ..color = background
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = w * 0.15,
        );
      case MoveLabel.good:
        canvas.drawPath(tick(), stroke);
      case MoveLabel.book:
        final page = Paint()..color = color;
        final left = Path()
          ..moveTo(w * 0.5, w * 0.22)
          ..quadraticBezierTo(w * 0.25, w * 0.1, w * 0.02, w * 0.2)
          ..lineTo(w * 0.02, w * 0.84)
          ..quadraticBezierTo(w * 0.25, w * 0.74, w * 0.5, w * 0.88)
          ..close();
        final right = Path()
          ..moveTo(w * 0.5, w * 0.22)
          ..quadraticBezierTo(w * 0.75, w * 0.1, w * 0.98, w * 0.2)
          ..lineTo(w * 0.98, w * 0.84)
          ..quadraticBezierTo(w * 0.75, w * 0.74, w * 0.5, w * 0.88)
          ..close();
        canvas.drawPath(left, page);
        canvas.drawPath(right, page);
        canvas.drawLine(
          Offset(w / 2, w * 0.22),
          Offset(w / 2, w * 0.88),
          Paint()
            ..color = background
            ..strokeWidth = w * 0.07,
        );
      case MoveLabel.forced:
        canvas.drawLine(Offset(w * 0.08, w / 2), Offset(w * 0.9, w / 2), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.55, w * 0.15)
            ..lineTo(w * 0.92, w / 2)
            ..lineTo(w * 0.55, w * 0.85),
          stroke,
        );
      case MoveLabel.miss:
        canvas.drawLine(Offset(w * 0.12, w * 0.12), Offset(w * 0.88, w * 0.88), stroke);
        canvas.drawLine(Offset(w * 0.88, w * 0.12), Offset(w * 0.12, w * 0.88), stroke);
      case MoveLabel.brilliant:
      case MoveLabel.great:
      case MoveLabel.inaccuracy:
      case MoveLabel.mistake:
      case MoveLabel.blunder:
        break; // text badges
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.label != label || old.color != color || old.background != background;
}
