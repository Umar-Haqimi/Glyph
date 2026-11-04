import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// About and licences. The full screen (F20) lands in M8.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.appTitle, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(l10n.aboutLicenseNotice),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => showLicensePage(context: context),
            child: Text(l10n.aboutLicenses),
          ),
        ],
      ),
    );
  }
}
