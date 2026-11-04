import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../theme/theme_providers.dart';

/// Settings. M1 only has the appearance section, to exercise Riverpod end to end.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final dynamicColor = ref.watch(dynamicColorProvider);
    final modes = <(ThemeMode, String)>[
      (ThemeMode.system, l10n.settingsThemeSystem),
      (ThemeMode.light, l10n.settingsThemeLight),
      (ThemeMode.dark, l10n.settingsThemeDark),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.settingsAppearance,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(title: Text(l10n.settingsThemeMode)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                for (final (mode, title) in modes)
                  ButtonSegment<ThemeMode>(value: mode, label: Text(title)),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) =>
                  ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
          SwitchListTile(
            title: Text(l10n.settingsDynamicColor),
            subtitle: Text(l10n.settingsDynamicColorSubtitle),
            value: dynamicColor,
            onChanged: (v) => ref.read(dynamicColorProvider.notifier).set(v),
          ),
          const Divider(),
          ListTile(
            title: Text(l10n.settingsAbout),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(Routes.about),
          ),
        ],
      ),
    );
  }
}
