import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

/// Background and foreground colour of one move-classification badge.
@immutable
class BadgeStyle {
  const BadgeStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  static BadgeStyle lerp(BadgeStyle a, BadgeStyle b, double t) => BadgeStyle(
    background: Color.lerp(a.background, b.background, t)!,
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is BadgeStyle &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}

/// Colours of the 11 classification badges (SPEC section 4), light and dark.
///
/// Badges are never colour-only: the glyph text is always drawn on top. The
/// pair for every label keeps a WCAG contrast ratio of at least 4.5:1, which
/// `test/theme/badge_colors_test.dart` verifies for both themes.
@immutable
class BadgeColors extends ThemeExtension<BadgeColors> {
  const BadgeColors._(this._styles);

  final Map<MoveLabel, BadgeStyle> _styles;

  /// Style for [label].
  BadgeStyle of(MoveLabel label) => _styles[label]!;

  static const Color _onLight = Color(0xFFFFFFFF);
  static const Color _onDark = Color(0xFF1B1B1B);

  static const BadgeColors light = BadgeColors._({
    MoveLabel.brilliant: BadgeStyle(background: Color(0xFF00796B), foreground: _onLight),
    MoveLabel.great: BadgeStyle(background: Color(0xFF1565C0), foreground: _onLight),
    MoveLabel.best: BadgeStyle(background: Color(0xFF2E7D32), foreground: _onLight),
    MoveLabel.excellent: BadgeStyle(background: Color(0xFF4B7A1E), foreground: _onLight),
    MoveLabel.good: BadgeStyle(background: Color(0xFF587566), foreground: _onLight),
    MoveLabel.book: BadgeStyle(background: Color(0xFF8A6A48), foreground: _onLight),
    MoveLabel.forced: BadgeStyle(background: Color(0xFF616161), foreground: _onLight),
    MoveLabel.inaccuracy: BadgeStyle(background: Color(0xFFF2B01E), foreground: _onDark),
    MoveLabel.mistake: BadgeStyle(background: Color(0xFFBF4A00), foreground: _onLight),
    MoveLabel.miss: BadgeStyle(background: Color(0xFFAD1457), foreground: _onLight),
    MoveLabel.blunder: BadgeStyle(background: Color(0xFFC62828), foreground: _onLight),
  });

  static const BadgeColors dark = BadgeColors._({
    MoveLabel.brilliant: BadgeStyle(background: Color(0xFF4DB6AC), foreground: _onDark),
    MoveLabel.great: BadgeStyle(background: Color(0xFF64B5F6), foreground: _onDark),
    MoveLabel.best: BadgeStyle(background: Color(0xFF81C784), foreground: _onDark),
    MoveLabel.excellent: BadgeStyle(background: Color(0xFFAED581), foreground: _onDark),
    MoveLabel.good: BadgeStyle(background: Color(0xFF9DBBA8), foreground: _onDark),
    MoveLabel.book: BadgeStyle(background: Color(0xFFD2B48C), foreground: _onDark),
    MoveLabel.forced: BadgeStyle(background: Color(0xFFBDBDBD), foreground: _onDark),
    MoveLabel.inaccuracy: BadgeStyle(background: Color(0xFFFFD54F), foreground: _onDark),
    MoveLabel.mistake: BadgeStyle(background: Color(0xFFFFA45C), foreground: _onDark),
    MoveLabel.miss: BadgeStyle(background: Color(0xFFF06292), foreground: _onDark),
    MoveLabel.blunder: BadgeStyle(background: Color(0xFFEF5350), foreground: _onDark),
  });

  static BadgeColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  BadgeColors copyWith({Map<MoveLabel, BadgeStyle>? styles}) =>
      BadgeColors._(styles ?? _styles);

  @override
  BadgeColors lerp(ThemeExtension<BadgeColors>? other, double t) {
    if (other is! BadgeColors) return this;
    return BadgeColors._({
      for (final label in MoveLabel.values)
        label: BadgeStyle.lerp(of(label), other.of(label), t),
    });
  }
}
