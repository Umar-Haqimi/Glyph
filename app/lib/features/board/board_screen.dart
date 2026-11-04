import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../engine/engine_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../widgets/placeholder_body.dart';
import '../explain/explain_sheet.dart';
import 'analysis_progress.dart';

/// Analysis board. Placeholder until M5; it already knows which game it shows.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, this.gameId});

  final int? gameId;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  bool _autoStarted = false;

  /// A game that was never analysed starts analysing when its board opens
  /// (SPEC section 4, import flow). Anything already stored is resumed by hand.
  void _maybeAutoStart(GameRecord? game) {
    if (_autoStarted || game == null || game.analysisStatus != null) return;
    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(analysisJobProvider.notifier).analyse(game);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.gameId;
    final game = id == null ? null : ref.watch(gameProvider(id)).value;
    _maybeAutoStart(game);
    final title = game == null
        ? l10n.boardTitle
        : l10n.boardTitleGame(
            game.white ?? l10n.libraryUnknownPlayer,
            game.black ?? l10n.libraryUnknownPlayer,
          );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (game != null) AnalysisProgress(game: game),
          const Expanded(child: PlaceholderBody()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.report),
                child: Text(l10n.boardReport),
              ),
              FilledButton.tonal(
                onPressed: () => showExplainSheet(context),
                child: Text(l10n.boardExplain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
