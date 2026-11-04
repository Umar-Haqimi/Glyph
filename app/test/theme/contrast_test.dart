import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/routes.dart';
import 'package:glyph/theme/app_theme.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/contrast.dart';
import '../support/test_app.dart';

/// M8 contrast checks: the colour pairs the app draws text and icons with, in
/// the seed theme (the fallback when dynamic colour is off or unavailable) in
/// both brightnesses, plus the screens rendered and measured. Badge pairs have
/// their own test (`badge_colors_test.dart`). A wallpaper-derived dynamic
/// scheme is Material-You-generated and cannot be pinned here.
void main() {
  final themes = buildThemes();
  for (final entry in {'light': themes.light, 'dark': themes.dark}.entries) {
    final s = entry.value.colorScheme;
    group('${entry.key} seed theme', () {
      final text = <String, (Color, Color)>{
        'body text on the page': (s.onSurface, s.surface),
        'secondary text on the page': (s.onSurfaceVariant, s.surface),
        'secondary text on a card': (s.onSurfaceVariant, s.surfaceContainerHighest),
        'text on a card': (s.onSurface, s.surfaceContainerHighest),
        'text on a primary button': (s.onPrimary, s.primary),
        'text on a tonal button / chip': (s.onSecondaryContainer, s.secondaryContainer),
        'text on a primary container (clock, selected chip)': (s.onPrimaryContainer, s.primaryContainer),
        'error text on the page': (s.error, s.surface),
        'text on an error container': (s.onErrorContainer, s.errorContainer),
        'text on the inverse snackbar': (s.onInverseSurface, s.inverseSurface),
        'snackbar action': (s.inversePrimary, s.inverseSurface),
        'text on the tertiary container': (s.onTertiaryContainer, s.tertiaryContainer),
      };
      for (final e in text.entries) {
        test('${e.key}: at least 4.5:1', () {
          expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5));
        });
      }

      final graphics = <String, (Color, Color)>{
        'primary (icons, arrow, selected) on the page': (s.primary, s.surface),
        'outline (borders of inputs and the gauge) on the page': (s.outline, s.surface),
      };
      for (final e in graphics.entries) {
        test('${e.key}: at least 3:1 (non-text UI)', () {
          expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(3));
        });
      }

      test('the gauge and the strips use fixed light/dark discs that stay legible on either theme', () {
        const white = Color(0xFFF4F4F4);
        const black = Color(0xFF262626);
        expect(contrast(black, white), greaterThanOrEqualTo(7), reason: 'gauge number on its two halves');
        // The disc beside a player's name is told apart from the page by its outline.
        expect(contrast(s.outline, s.surface), greaterThanOrEqualTo(3));
      });
    });
  }

  group('rendered screens meet the text contrast guideline (no images behind the text)', () {
    for (final brightness in Brightness.values) {
      for (final entry in {
        'library (empty)': null,
        'settings': Routes.settings,
        'about': Routes.about,
      }.entries) {
        testWidgets('${entry.key}, ${brightness.name}', (tester) async {
          final handle = tester.ensureSemantics();
          tester.view.physicalSize = const Size(360, 740);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(() {
            tester.view.reset();
            tester.platformDispatcher.clearPlatformBrightnessTestValue();
          });
          final env = TestEnv();
          await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const GlyphApp()));
          await tester.pumpAndSettle();
          if (entry.value != null) {
            tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(entry.value!);
            await tester.pumpAndSettle();
          }
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  test('the badge palette has 11 labels (checked in badge_colors_test)', () {
    expect(MoveLabel.values, hasLength(11));
  });
}
