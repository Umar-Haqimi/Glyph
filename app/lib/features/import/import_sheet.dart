import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/file_picker_service.dart';
import 'import_preview_screen.dart';
import 'paste_import_screen.dart';
import 'pgn_issue_text.dart';

/// Opens the import sheet (SPEC section 4, screen 2).
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const ImportSheet(),
  );
}

class ImportSheet extends ConsumerWidget {
  const ImportSheet({super.key});

  void _paste(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => const PasteImportScreen()));
  }

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final picker = ref.read(filePickerServiceProvider);

    Future<void> fail(String message) async {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
            ),
          ],
        ),
      );
      if (context.mounted) navigator.pop();
    }

    final PickedPgn? picked;
    try {
      picked = await picker.pickPgn();
    } catch (_) {
      return fail(l10n.importFileOpenFailed);
    }
    if (picked == null) return; // cancelled: stay on the sheet
    if (picked.tooLarge) return fail(l10n.importErrorTooLarge);
    final result = await parsePgnBytesAsync(picked.bytes!);
    if (result is PgnFailed) return fail(pgnIssueText(l10n, result.issue));
    if (!context.mounted) return;
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => ImportPreviewScreen(result: result, source: GameSource.file),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Widget row(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          minTileHeight: 56,
          enabled: onTap != null,
          onTap: onTap,
        );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(l10n.importSheetTitle, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          row(Icons.content_paste, l10n.importPastePgn, onTap: () => _paste(context)),
          row(Icons.folder_open, l10n.importOpenFile, onTap: () => _openFile(context, ref)),
          row(Icons.public, l10n.importFromLichess, subtitle: l10n.importComingSoon),
          row(Icons.public, l10n.importFromChessCom, subtitle: l10n.importComingSoon),
        ],
      ),
    );
  }
}
