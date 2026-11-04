import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/settings/appearance_settings.dart';

/// Light / dark / follow-system, from the stored appearance settings
/// (`appearanceProvider` owns the choice and persists it).
final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(appearanceProvider.select((a) => a.themeMode)));

/// Whether to use the system (wallpaper) palette on Android 12+.
final dynamicColorProvider = Provider<bool>((ref) => ref.watch(appearanceProvider.select((a) => a.dynamicColor)));
