import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/app_log.dart';
import '../../platform/pgn_share_service.dart';
import 'pgn_export_service.dart';

/// Export PGN (board menu and library card): builds the annotated PGN and opens
/// the system share sheet. A failure shows a SnackBar and logs the error type.
Future<void> exportGamePgn(BuildContext context, WidgetRef ref, int gameId) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void fail() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
  try {
    final exported = await ref.read(pgnExportServiceProvider).build(gameId);
    if (exported == null) return fail();
    await ref.read(pgnShareServiceProvider).share(
          pgn: exported.pgn,
          fileName: exported.fileName,
          title: l10n.exportShareTitle,
        );
  } on Object catch (e) {
    AppLog.warning('Exporting a game failed', e);
    fail();
  }
}
