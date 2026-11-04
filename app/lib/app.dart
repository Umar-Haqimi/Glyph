import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n/app_localizations.dart';
import 'routes.dart';
import 'theme/app_theme.dart';
import 'theme/theme_providers.dart';

class GlyphApp extends ConsumerWidget {
  const GlyphApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final useDynamic = ref.watch(dynamicColorProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final themes = buildThemes(
          dynamicLight: useDynamic ? lightDynamic?.harmonized() : null,
          dynamicDark: useDynamic ? darkDynamic?.harmonized() : null,
        );
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: themes.light,
          darkTheme: themes.dark,
          themeMode: themeMode,
          // gen-l10n's own delegate list points at the legacy flutter/material
          // classes; material_ui's delegates are used instead (libraries.md section 4).
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: Routes.library,
          onGenerateRoute: Routes.onGenerateRoute,
        );
      },
    );
  }
}
