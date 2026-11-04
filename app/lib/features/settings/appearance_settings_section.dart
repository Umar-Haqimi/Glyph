import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/adaptive_segments.dart';
import '../../widgets/choice_option.dart';
import '../../widgets/section_header.dart';
import '../board/board_assets.dart';
import '../board/board_preview.dart';
import 'appearance_settings.dart';

/// The display name of a board colour scheme key of `selectableBoardSchemes`.
String boardSchemeName(AppLocalizations l10n, String key) => switch (key) {
      'brown' => l10n.boardScheme_brown,
      'blue' => l10n.boardScheme_blue,
      'green' => l10n.boardScheme_green,
      'ic' => l10n.boardScheme_ic,
      'blue2' => l10n.boardScheme_blue2,
      'blue3' => l10n.boardScheme_blue3,
      'blueMarble' => l10n.boardScheme_blueMarble,
      'canvas' => l10n.boardScheme_canvas,
      'greenPlastic' => l10n.boardScheme_greenPlastic,
      'grey' => l10n.boardScheme_grey,
      'leather' => l10n.boardScheme_leather,
      'maple' => l10n.boardScheme_maple,
      'maple2' => l10n.boardScheme_maple2,
      'marble' => l10n.boardScheme_marble,
      'metal' => l10n.boardScheme_metal,
      'olive' => l10n.boardScheme_olive,
      'pinkPyramid' => l10n.boardScheme_pinkPyramid,
      'purple' => l10n.boardScheme_purple,
      'purpleDiag' => l10n.boardScheme_purpleDiag,
      'wood' => l10n.boardScheme_wood,
      'wood2' => l10n.boardScheme_wood2,
      'wood3' => l10n.boardScheme_wood3,
      'wood4' => l10n.boardScheme_wood4,
      _ => key,
    };

/// The display name of a piece set key of `selectablePieceSets`.
String pieceSetName(AppLocalizations l10n, String key) => switch (key) {
      'cburnett' => l10n.pieceSet_cburnett,
      'merida' => l10n.pieceSet_merida,
      'mpchess' => l10n.pieceSet_mpchess,
      'rhosgfx' => l10n.pieceSet_rhosgfx,
      _ => key,
    };

/// Settings > Appearance (SPEC F19): theme, dynamic colour, board colours and
/// piece set (only the free-licensed ones of `board_assets.dart`), move sounds.
class AppearanceSettingsSection extends ConsumerWidget {
  const AppearanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final modes = <(ThemeMode, String)>[
      (ThemeMode.system, l10n.settingsThemeSystem),
      (ThemeMode.light, l10n.settingsThemeLight),
      (ThemeMode.dark, l10n.settingsThemeDark),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.settingsAppearance),
        ListTile(title: Text(l10n.settingsThemeMode)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdaptiveSegments<ThemeMode>(
            controlKey: const Key('settings-theme'),
            options: modes,
            selected: appearance.themeMode,
            onChanged: notifier.setThemeMode,
          ),
        ),
        SwitchListTile(
          key: const Key('settings-dynamic-color'),
          title: Text(l10n.settingsDynamicColor),
          subtitle: Text(l10n.settingsDynamicColorSubtitle),
          value: appearance.dynamicColor,
          onChanged: notifier.setDynamicColor,
        ),
        ListTile(
          key: const Key('settings-board-theme'),
          title: Text(l10n.settingsBoardTheme),
          subtitle: Text(boardSchemeName(l10n, appearance.boardScheme)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final choice = await showChoiceDialog<String>(
              context,
              title: l10n.settingsBoardTheme,
              options: [for (final key in selectableBoardSchemes.keys) (key, boardSchemeName(l10n, key))],
              selected: appearance.boardScheme,
              keyPrefix: 'board-scheme',
            );
            if (choice != null) notifier.setBoardScheme(choice);
          },
        ),
        ListTile(
          key: const Key('settings-piece-set'),
          title: Text(l10n.settingsPieceSet),
          subtitle: Text(pieceSetName(l10n, appearance.pieceSet)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final choice = await showChoiceDialog<String>(
              context,
              title: l10n.settingsPieceSet,
              options: [for (final key in selectablePieceSets.keys) (key, pieceSetName(l10n, key))],
              selected: appearance.pieceSet,
              keyPrefix: 'piece-set',
            );
            if (choice != null) notifier.setPieceSet(choice);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: BoardPreview(key: const Key('settings-board-preview'), schemeKey: appearance.boardScheme, pieceSetKey: appearance.pieceSet),
          ),
        ),
        SwitchListTile(
          key: const Key('settings-move-sounds'),
          title: Text(l10n.settingsMoveSounds),
          subtitle: Text(l10n.settingsMoveSoundsSubtitle),
          value: appearance.moveSounds,
          onChanged: notifier.setMoveSounds,
        ),
      ],
    );
  }
}
