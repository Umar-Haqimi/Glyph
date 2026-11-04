import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import 'accounts_settings_section.dart';
import 'appearance_settings_section.dart';
import 'data_settings_section.dart';
import 'engine_settings_section.dart';
import 'explanation_settings_section.dart';

/// Settings (SPEC section 4, screen 6): Engine, Explanations, Accounts,
/// Appearance, Data, About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            const EngineSettingsSection(),
            const Divider(),
            const ExplanationSettingsSection(),
            const Divider(),
            const AccountsSettingsSection(),
            const Divider(),
            const AppearanceSettingsSection(),
            const Divider(),
            const DataSettingsSection(),
            const Divider(),
            ListTile(
              key: const Key('settings-about'),
              title: Text(l10n.settingsAbout),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed(Routes.about),
            ),
          ],
        ),
      ),
    );
  }
}
