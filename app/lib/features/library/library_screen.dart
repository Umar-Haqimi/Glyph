import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../engine/engine_providers.dart';
import '../../l10n/app_localizations.dart';
import '../errors/failure_text.dart';
import '../errors/recovery.dart';
import '../../routes.dart';
import '../export/export_pgn.dart';
import '../import/import_sheet.dart';
import 'game_text.dart';
import 'library_controller.dart';

/// Home screen: the game library (SPEC screen 1).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final games = ref.watch(libraryProvider);
    // Once per session: re-label analysed games after a classifier change.
    ref.watch(classifierUpkeepProvider);
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
      body: games.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(liveRegion: true, child: Text(appFailureText(l10n, AppFailure.libraryLoad), textAlign: TextAlign.center)),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('library-retry'),
                  onPressed: () => ref.invalidate(libraryProvider),
                  child: Text(l10n.libraryRetry),
                ),
              ],
            ),
          ),
        ),
        data: (list) => list.isEmpty ? const _EmptyState() : _GameList(games: list),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showImportSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.libraryImportFab),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_rounded, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(l10n.libraryEmptyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => showImportSheet(context),
              child: Text(l10n.libraryEmptyAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameList extends ConsumerWidget {
  const _GameList({required this.games});

  final List<GameRecord> games;

  void _onDismissed(BuildContext context, WidgetRef ref, GameRecord game) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(libraryProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    controller.requestDelete(game.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.libraryGameDeleted),
          // A SnackBar with an action persists by default; the undo window must end.
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: l10n.libraryUndo, onPressed: () => controller.undoDelete(game.id)),
        ),
      ).closed.then((_) => controller.commitDelete(game.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: games.length,
      itemBuilder: (context, i) {
        final game = games[i];
        return Dismissible(
          key: ValueKey('game-${game.id}'),
          background: _swipeBackground(scheme, Alignment.centerLeft),
          secondaryBackground: _swipeBackground(scheme, Alignment.centerRight),
          onDismissed: (_) => _onDismissed(context, ref, game),
          child: GameCard(game: game),
        );
      },
    );
  }

  Widget _swipeBackground(ColorScheme scheme, Alignment alignment) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
        alignment: alignment,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      );
}

/// One game in the library.
class GameCard extends ConsumerWidget {
  const GameCard({super.key, required this.game});

  final GameRecord game;

  String _player(AppLocalizations l10n, String? name, int? elo) {
    final n = name ?? l10n.libraryUnknownPlayer;
    return elo == null ? n : l10n.libraryPlayerWithElo(n, elo);
  }

  String _source(AppLocalizations l10n) => switch (game.source) {
        GameSource.paste => l10n.librarySourcePaste,
        GameSource.file => l10n.librarySourceFile,
        GameSource.share => l10n.librarySourceShare,
        GameSource.lichess => l10n.librarySourceLichess,
        GameSource.chesscom => l10n.librarySourceChessCom,
      };

  String _analysis(AppLocalizations l10n) {
    final percent = game.analysisPercent;
    return switch (game.analysisStatus) {
      null => l10n.libraryAnalysisNone,
      AnalysisStatus.completed => l10n.libraryAnalysisDone,
      AnalysisStatus.running => l10n.libraryAnalysisRunning(percent),
      _ => l10n.libraryAnalysisPartial(percent),
    };
  }

  static String _accuracy(double v) => Accuracy.display(v).toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chips = <String>[
      formatResult(game.result),
      if (game.date != null) formatDate(game.date!),
      l10n.libraryMoveCount((game.plyCount + 1) ~/ 2),
      _source(l10n),
      if (game.variant == GameVariant.chess960) l10n.libraryChess960,
      _analysis(l10n),
      if (game.whiteAccuracy != null) l10n.libraryAccuracyWhite(_accuracy(game.whiteAccuracy!)),
      if (game.blackAccuracy != null) l10n.libraryAccuracyBlack(_accuracy(game.blackAccuracy!)),
      if (game.userSide == Side.white) l10n.libraryYouWhite,
      if (game.userSide == Side.black) l10n.libraryYouBlack,
    ];
    final opening = [
      if (game.eco != null) game.eco!,
      if (game.openingName != null) game.openingName!,
    ].join(' · ');
    final title = l10n.libraryGameTitle(
      _player(l10n, game.white, game.whiteElo),
      _player(l10n, game.black, game.blackElo),
    );
    void open() => Navigator.of(context).pushNamed(Routes.board, arguments: game.id);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // One node for a screen reader: players, result, date, moves, source,
          // analysis state, accuracy and side read as one sentence and the card
          // opens the game; the menu button stays a node of its own.
          Semantics(
            container: true,
            button: true,
            label: l10n.libraryCardSemantics(title, [if (opening.isNotEmpty) opening, ...chips].join(', ')),
            onTap: open,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Room for the 48 dp menu button at the top right.
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 36),
                        child: Text(title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      if (opening.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(opening, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final c in chips)
                            Chip(
                              label: Text(c),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelStyle: theme.textTheme.labelMedium,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: PopupMenuButton<_CardAction>(
              key: Key('game-menu-${game.id}'),
              tooltip: l10n.boardMenuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _CardAction.export:
                    exportGamePgn(context, ref, game.id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: Key('game-export-${game.id}'),
                  value: _CardAction.export,
                  child: Text(l10n.exportPgn),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CardAction { export }
