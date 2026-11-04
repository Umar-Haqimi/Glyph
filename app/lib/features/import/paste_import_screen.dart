import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import 'import_service.dart';
import 'parse_result_view.dart';

/// Inputs longer than this are re-validated after a short pause instead of on
/// every keystroke.
const int _debounceThreshold = 20000;

/// Import > Paste PGN: text field with live validation, game picker, Save.
class PasteImportScreen extends ConsumerStatefulWidget {
  const PasteImportScreen({super.key});

  @override
  ConsumerState<PasteImportScreen> createState() => _PasteImportScreenState();
}

class _PasteImportScreenState extends ConsumerState<PasteImportScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  PgnParseResult? _result;
  int? _selected;
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final seq = ++_seq;
    if (text.trim().isEmpty) {
      setState(() {
        _result = null;
        _selected = null;
      });
      return;
    }
    if (text.length > _debounceThreshold) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _validate(seq, text));
    } else {
      _validate(seq, text);
    }
  }

  Future<void> _validate(int seq, String text) async {
    final result = await parsePgnAsync(text);
    if (!mounted || seq != _seq) return; // a newer edit superseded this one
    setState(() {
      _result = result;
      _selected = result.games.length == 1 ? 0 : null;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    _controller.text = text;
    _onChanged(text);
  }

  Future<void> _save() async {
    final result = _result;
    final selected = _selected;
    if (result == null || selected == null || _saving) return;
    setState(() => _saving = true);
    final saved = await ref.read(importServiceProvider).save(result.games[selected], GameSource.paste);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.board, arguments: saved.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importPasteTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: [
                  TextField(
                    key: const Key('pgnField'),
                    controller: _controller,
                    onChanged: _onChanged,
                    minLines: 6,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: l10n.importPasteHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste),
                        label: Text(l10n.importPasteFromClipboard),
                      ),
                      TextButton(
                        onPressed: _controller.text.isEmpty
                            ? null
                            : () {
                                _controller.clear();
                                _onChanged('');
                              },
                        child: Text(l10n.importClear),
                      ),
                    ],
                  ),
                  ParseResultView(
                    result: _result,
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
