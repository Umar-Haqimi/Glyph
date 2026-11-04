import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/app_log.dart';
import '../board/board_assets.dart';

/// Appearance and feedback settings (SPEC F19): theme, dynamic colour, board
/// colours, piece set, move sounds. Stored in the `settings` table; the board
/// and piece choices are keys of the allow-lists in `board_assets.dart`, so a
/// stored value that is not on the list (an old install, a hand-edited
/// database) falls back to the default instead of naming a missing asset.
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.dynamicColor = true,
    this.boardScheme = defaultBoardSchemeKey,
    this.pieceSet = defaultPieceSetKey,
    this.moveSounds = false,
  });

  final ThemeMode themeMode;
  final bool dynamicColor;

  /// A key of [selectableBoardSchemes].
  final String boardScheme;

  /// A key of [selectablePieceSets].
  final String pieceSet;

  /// A click when a single move is stepped on the board. Off by default.
  final bool moveSounds;

  AppearanceSettings copyWith({
    ThemeMode? themeMode,
    bool? dynamicColor,
    String? boardScheme,
    String? pieceSet,
    bool? moveSounds,
  }) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        dynamicColor: dynamicColor ?? this.dynamicColor,
        boardScheme: boardScheme ?? this.boardScheme,
        pieceSet: pieceSet ?? this.pieceSet,
        moveSounds: moveSounds ?? this.moveSounds,
      );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.themeMode == themeMode &&
      other.dynamicColor == dynamicColor &&
      other.boardScheme == boardScheme &&
      other.pieceSet == pieceSet &&
      other.moveSounds == moveSounds;

  @override
  int get hashCode => Object.hash(themeMode, dynamicColor, boardScheme, pieceSet, moveSounds);

  /// Reads the stored values; anything missing or not recognised is the default.
  static Future<AppearanceSettings> load(SettingsRepository repo) async {
    final mode = await repo.get(SettingsKeys.themeMode);
    final dynamic = await repo.get(SettingsKeys.dynamicColor);
    final scheme = await repo.get(SettingsKeys.boardScheme);
    final pieces = await repo.get(SettingsKeys.pieceSet);
    final sounds = await repo.get(SettingsKeys.moveSounds);
    return AppearanceSettings(
      themeMode: ThemeMode.values.where((m) => m.name == mode).firstOrNull ?? ThemeMode.system,
      dynamicColor: dynamic != '0',
      boardScheme: selectableBoardSchemes.containsKey(scheme) ? scheme! : defaultBoardSchemeKey,
      pieceSet: selectablePieceSets.containsKey(pieces) ? pieces! : defaultPieceSetKey,
      moveSounds: sounds == '1',
    );
  }
}

/// `main()` reads the stored appearance before the first frame (no flash of the
/// wrong theme) and passes it here; tests leave it null and the notifier loads
/// from the repository.
final initialAppearanceProvider = Provider<AppearanceSettings?>((ref) => null);

class AppearanceNotifier extends Notifier<AppearanceSettings> {
  bool _touched = false;

  @override
  AppearanceSettings build() {
    final initial = ref.watch(initialAppearanceProvider);
    if (initial != null) return initial;
    unawaited(_load());
    return const AppearanceSettings();
  }

  Future<void> _load() async {
    try {
      final loaded = await AppearanceSettings.load(ref.read(settingsRepositoryProvider));
      // A choice made while the read was in flight wins.
      if (ref.mounted && !_touched) state = loaded;
    } on Object catch (e) {
      AppLog.warning('Reading the appearance settings failed', e);
    }
  }

  void setThemeMode(ThemeMode mode) => _set(state.copyWith(themeMode: mode), SettingsKeys.themeMode, mode.name);

  void setDynamicColor(bool on) => _set(state.copyWith(dynamicColor: on), SettingsKeys.dynamicColor, on ? '1' : '0');

  /// Ignores a key that is not on the allow-list.
  void setBoardScheme(String key) {
    if (!selectableBoardSchemes.containsKey(key)) return;
    _set(state.copyWith(boardScheme: key), SettingsKeys.boardScheme, key);
  }

  /// Ignores a key that is not on the allow-list.
  void setPieceSet(String key) {
    if (!selectablePieceSets.containsKey(key)) return;
    _set(state.copyWith(pieceSet: key), SettingsKeys.pieceSet, key);
  }

  void setMoveSounds(bool on) => _set(state.copyWith(moveSounds: on), SettingsKeys.moveSounds, on ? '1' : '0');

  /// Back to the defaults (after "Delete all data").
  void reset() {
    _touched = true;
    state = const AppearanceSettings();
  }

  void _set(AppearanceSettings next, String key, String value) {
    _touched = true;
    state = next;
    unawaited(_save(key, value));
  }

  Future<void> _save(String key, String value) async {
    try {
      await ref.read(settingsRepositoryProvider).set(key, value);
    } on Object catch (e) {
      AppLog.warning('Saving an appearance setting failed', e);
    }
  }
}

final appearanceProvider = NotifierProvider<AppearanceNotifier, AppearanceSettings>(AppearanceNotifier.new);
