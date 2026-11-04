import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// User choice of light / dark / follow-system. Persisted in a later milestone.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Whether to use the system (wallpaper) palette on Android 12+.
class DynamicColorNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool enabled) => state = enabled;
}

final dynamicColorProvider = NotifierProvider<DynamicColorNotifier, bool>(
  DynamicColorNotifier.new,
);
