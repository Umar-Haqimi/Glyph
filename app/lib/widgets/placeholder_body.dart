import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// Centered "coming later" text used by screens that are not built yet.
class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.placeholderComingSoon,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
