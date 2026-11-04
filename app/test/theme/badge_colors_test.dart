import 'dart:math' as math;

import 'package:glyph/theme/app_theme.dart';
import 'package:glyph/theme/badge_colors.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// WCAG 2.x contrast ratio.
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('BadgeColors', () {
    for (final entry in {
      'light': BadgeColors.light,
      'dark': BadgeColors.dark,
    }.entries) {
      test('${entry.key}: all 11 labels have a style', () {
        for (final label in MoveLabel.values) {
          expect(() => entry.value.of(label), returnsNormally, reason: '$label');
        }
        expect(MoveLabel.values, hasLength(11));
      });

      test('${entry.key}: glyph/background contrast is at least 4.5:1', () {
        for (final label in MoveLabel.values) {
          final style = entry.value.of(label);
          expect(
            contrastRatio(style.background, style.foreground),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.key} $label',
          );
        }
      });
    }

    test('badge backgrounds are distinct within a theme', () {
      for (final colors in [BadgeColors.light, BadgeColors.dark]) {
        final backgrounds = {
          for (final l in MoveLabel.values) colors.of(l).background,
        };
        expect(backgrounds, hasLength(MoveLabel.values.length));
      }
    });

    test('contrast helper sanity: black on white is 21:1', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 1e-9),
      );
    });

    test('theme attaches the matching extension per brightness', () {
      final themes = buildThemes();
      expect(themes.light.extension<BadgeColors>(), same(BadgeColors.light));
      expect(themes.dark.extension<BadgeColors>(), same(BadgeColors.dark));
    });

    test('lerp interpolates and copyWith keeps styles', () {
      final mid = BadgeColors.light.lerp(BadgeColors.dark, 0.5);
      final a = BadgeColors.light.of(MoveLabel.blunder).background;
      final b = BadgeColors.dark.of(MoveLabel.blunder).background;
      expect(mid.of(MoveLabel.blunder).background, Color.lerp(a, b, 0.5));
      expect(
        BadgeColors.light.copyWith().of(MoveLabel.best),
        BadgeColors.light.of(MoveLabel.best),
      );
    });
  });
}
