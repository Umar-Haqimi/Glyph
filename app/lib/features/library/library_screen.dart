import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../import/import_sheet.dart';

/// Home screen: the game library. M1 shows the empty state only.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => Navigator.of(context).pushNamed(Routes.settings),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(l10n.libraryEmptyTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => showImportSheet(context),
                child: Text(l10n.libraryEmptyAction),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.board),
                child: Text(l10n.libraryOpenSampleBoard),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showImportSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.libraryImportFab),
      ),
    );
  }
}
