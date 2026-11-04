import 'package:material_ui/material_ui.dart';

import 'badge_colors.dart';

/// Fallback seed colour when dynamic colour is off or unavailable (pre Android 12).
const Color kSeedColor = Color(0xFF3F6B54);

/// Builds the Material 3 theme for [scheme] with the Glyph extensions attached.
ThemeData buildTheme(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[
      BadgeColors.forBrightness(scheme.brightness),
    ],
  );
}

/// Light and dark schemes: from the system palette when [dynamicLight] and
/// [dynamicDark] are given (Android 12+), otherwise from [kSeedColor].
({ThemeData light, ThemeData dark}) buildThemes({
  ColorScheme? dynamicLight,
  ColorScheme? dynamicDark,
}) {
  final light =
      dynamicLight ??
      ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.light);
  final dark =
      dynamicDark ??
      ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.dark);
  return (light: buildTheme(light), dark: buildTheme(dark));
}
