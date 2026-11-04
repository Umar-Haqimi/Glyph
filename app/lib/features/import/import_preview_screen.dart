import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_log.dart';
import '../../routes.dart';
import 'import_service.dart';
import 'parse_result_view.dart';

/// Pick-and-save screen for an already parsed result (file and share flows).
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({super.key, required this.result, required this.source});

  final PgnParseResult result;
  final GameSource source;

  @override
  ConsumerState<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  late int? _selected = widget.result.games.length == 1 ? 0 : null;
  bool _saving = false;

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    final SaveResult saved;
    try {
      saved = await ref.read(importServiceProvider).save(widget.result.games[selected], widget.source);
    } on Object catch (e) {
      AppLog.warning('Saving an imported game failed', e);
      if (!mounted) return;
      setState(() => _saving = false);
      showImportSaveFailed(context, _save);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.board, arguments: saved.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importFileTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  ParseResultView(
                    result: widget.result,
                    selected: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('importSave'),
                  onPressed: _selected == null || _saving ? null : _save,
                  child: Text(l10n.importSave),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
