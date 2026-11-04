import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Opens the import sheet (SPEC section 4, screen 2). Rows are placeholders in M1.
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const ImportSheet(),
  );
}

class ImportSheet extends StatelessWidget {
  const ImportSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <(IconData, String)>[
      (Icons.content_paste, l10n.importPastePgn),
      (Icons.folder_open, l10n.importOpenFile),
      (Icons.public, l10n.importFromLichess),
      (Icons.public, l10n.importFromChessCom),
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.importSheetTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          for (final (icon, title) in rows)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              minTileHeight: 56,
              onTap: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}
