import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../engine/engine_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../library/library_controller.dart';
import '../settings/engine_settings.dart';
import '../report/report_screen.dart';
import 'analysis_board.dart';
import 'analysis_progress.dart';
import 'board_data.dart';
import 'board_format.dart';
import 'coach.dart';
import 'coach_card.dart';
import 'engine_lines.dart';
import 'eval_gauge.dart';
import 'eval_graph.dart';
import 'key_moments_sheet.dart';
import 'move_badge.dart';
import 'move_list.dart';
import 'player_strip.dart';
import 'spoken_move.dart';

/// Analysis board (SPEC section 4, screen 3): the review experience without
/// the LLM. View-only in v1; all navigation goes through a [PositionCursor],
/// so variations can be added later (SPEC section 1, N2).
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key, this.gameId, this.initialPly = 0});

  final int? gameId;

  /// The position the board opens on (0 = start).
  final int initialPly;

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

enum _MenuAction { bestArrow, setSide, reanalyse, delete }

class _BoardScreenState extends ConsumerState<BoardScreen> {
  bool _autoStarted = false;

  PositionCursor? _cursor;
  bool _flipped = false;
  bool _showArrow = true;
  bool _linesExpanded = true;

  /// Whether the last move of the cursor was a single step (pieces glide);
  /// a jump over several plies shows the new position at once.
  bool _animate = true;

  /// A game that was never analysed starts analysing when its board opens
  /// (SPEC section 4, import flow). Anything already stored is resumed by
  /// hand. A game that is already queued or running is left alone (starting
  /// it again would move it to the back of the queue), and so is one whose
  /// queued job the user cancelled (the progress row offers Resume).
  void _maybeAutoStart(GameRecord? game) {
    if (_autoStarted || game == null || game.analysisStatus != null) return;
    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final jobs = ref.read(analysisJobProvider.notifier);
      if (jobs.isActive(game.id) || jobs.wasCancelledWhileQueued(game.id)) return;
      jobs.analyse(game);
    });
  }

  void _goTo(int ply) {
    final cursor = _cursor;
    if (cursor == null) return;
    final target = ply.clamp(0, cursor.length);
    if (target == cursor.ply) return;
    setState(() {
      _animate = (target - cursor.ply).abs() == 1;
      cursor.goTo(target);
    });
  }

  Side _orientation(BoardData data) {
    final base = data.userSide ?? Side.white;
    return _flipped ? base.opposite : base;
  }

  Future<void> _chooseSide(BoardData data) async {
    final l10n = AppLocalizations.of(context);
    const none = Object();
    final picked = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.boardYourSideTitle),
        children: [
          for (final (side, text) in [(Side.white, l10n.sideWhite), (Side.black, l10n.sideBlack)])
            _ChoiceOption(
              optionKey: Key('your-side-${side.name}'),
              onPressed: () => Navigator.of(context).pop(side),
              text: text,
              selected: data.userSide == side,
            ),
          _ChoiceOption(
            optionKey: const Key('your-side-none'),
            onPressed: () => Navigator.of(context).pop(none),
            text: l10n.boardYourSideNone,
            selected: data.userSide == null,
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final side = picked is Side ? picked : null;
    final id = data.record.id;
    await ref.read(gameRepositoryProvider).setUserSide(id, side);
    if (!mounted) return;
    setState(() => _flipped = false); // orient to the new side
    ref.invalidate(gameProvider(id));
    if (ref.exists(libraryProvider)) ref.read(libraryProvider.notifier).refresh();
  }

  Future<void> _chooseReanalyseDepth(BoardData data) async {
    final l10n = AppLocalizations.of(context);
    final current = (await ref.read(engineSettingsProvider.future)).preset;
    if (!mounted) return;
    final picked = await showDialog<DepthPreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.boardReanalyseTitle),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l10n.boardReanalyseNote, style: Theme.of(context).textTheme.bodySmall),
          ),
          for (final preset in DepthPreset.values)
            _ChoiceOption(
              optionKey: Key('reanalyse-${preset.name}'),
              onPressed: () => Navigator.of(context).pop(preset),
              text: l10n.boardReanalyseOption(_presetName(l10n, preset), preset.depth),
              selected: preset == current,
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _autoStarted = true);
    // The existing restart path: the stored lines, labels and accuracy are
    // thrown away when the job begins (a running job is cancelled first).
    await ref.read(analysisJobProvider.notifier).analyse(data.record, restart: true, depth: picked.depth);
  }

  String _presetName(AppLocalizations l10n, DepthPreset preset) => switch (preset) {
        DepthPreset.fast => l10n.depthFast,
        DepthPreset.normal => l10n.depthNormal,
        DepthPreset.deep => l10n.depthDeep,
      };

  Future<void> _confirmDelete(BoardData data) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.boardDeleteTitle),
        content: Text(l10n.boardDeleteBody),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.analysisCancel),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.libraryDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // The library's delete flow: stops the game's analysis (running or
    // queued) before the rows go away. Leave the board first so it never
    // shows a game that no longer exists.
    final library = ref.read(libraryProvider.notifier);
    final id = data.record.id;
    Navigator.of(context).maybePop();
    await library.deleteNow(id);
  }

  Future<void> _openKeyMoments(BoardData data) async {
    final ply = await showKeyMomentsSheet(context, data);
    if (ply != null) _goTo(ply);
  }

  Future<void> _openReport(BoardData data) async {
    // Typed route (a named route cannot return an int): the report hands back
    // the ply picked on its graph.
    final ply = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        settings: RouteSettings(name: Routes.report, arguments: data.record.id),
        builder: (_) => ReportScreen(gameId: data.record.id, initialPly: _cursor?.ply ?? 0),
      ),
    );
    if (ply != null) _goTo(ply);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.gameId;
    final game = id == null ? null : ref.watch(gameProvider(id)).value;
    _maybeAutoStart(game);
    if (id != null && game?.analysisStatus == AnalysisStatus.completed) {
      // Labels and accuracy for a completed analysis (M4).
      ref.listen(reviewDoneProvider(id), (_, next) {
        if (next.value == true) ref.invalidate(gameProvider(id));
      });
    }
    final dataAsync = id == null ? null : ref.watch(boardDataProvider(id));
    final data = dataAsync?.value;
    if (data != null) _cursor ??= MainlineCursor(data.game, ply: widget.initialPly);

    final title = game == null
        ? l10n.boardTitle
        : l10n.boardTitleGame(
            game.white ?? l10n.libraryUnknownPlayer,
            game.black ?? l10n.libraryUnknownPlayer,
          );

    final Widget content;
    if (id == null) {
      content = _Message(text: l10n.boardNoGame);
    } else if (data != null) {
      content = _buildBoard(context, l10n, data);
    } else if (dataAsync == null || dataAsync.isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = _Message(text: dataAsync.hasError ? l10n.boardLoadFailed : l10n.boardUnavailable);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (data != null) ...[
            IconButton(
              key: const Key('flip-board'),
              tooltip: l10n.boardFlip,
              onPressed: () => setState(() => _flipped = !_flipped),
              icon: const Icon(Icons.flip),
            ),
            PopupMenuButton<_MenuAction>(
              key: const Key('board-menu'),
              tooltip: l10n.boardMenuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _MenuAction.bestArrow:
                    setState(() => _showArrow = !_showArrow);
                  case _MenuAction.setSide:
                    _chooseSide(data);
                  case _MenuAction.reanalyse:
                    _chooseReanalyseDepth(data);
                  case _MenuAction.delete:
                    _confirmDelete(data);
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  key: const Key('menu-best-arrow'),
                  value: _MenuAction.bestArrow,
                  checked: _showArrow,
                  child: Text(l10n.boardShowBestArrow),
                ),
                PopupMenuItem(
                  key: const Key('menu-set-side'),
                  value: _MenuAction.setSide,
                  child: Text(l10n.boardSetYourSide),
                ),
                PopupMenuItem(
                  key: const Key('menu-reanalyse'),
                  value: _MenuAction.reanalyse,
                  child: Text(l10n.boardMenuReanalyse),
                ),
                PopupMenuItem(
                  key: const Key('menu-delete'),
                  value: _MenuAction.delete,
                  child: Text(l10n.boardMenuDelete),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (game != null) AnalysisProgress(game: game),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: data == null ? null : _buildBottomBar(context, l10n, data),
    );
  }

  Widget _buildBoard(BuildContext context, AppLocalizations l10n, BoardData data) {
    final cursor = _cursor!;
    final ply = cursor.ply;
    final orientation = _orientation(data);
    final position = cursor.position;
    final eval = evalDisplayAt(data, l10n, ply);
    final coach = coachLineAt(data, l10n, ply);

    // The move just played: highlight, badge square (castling = the king's
    // landing square) and the screen-reader description.
    NormalMove? lastMove;
    BoardBadge? badge;
    String? moveText;
    final move = ply >= 1 ? Move.parse(data.game.plies[ply - 1].uci) : null;
    if (move is NormalMove) {
      final before = data.positionBefore(ply);
      lastMove = displayMove(before, move);
      // Words for the screen reader ("Move 12, White: Knight f3"), not SAN.
      moveText = spokenMove(l10n, before, data.game.plies[ply - 1].san);
      final label = data.moveAt(ply)?.label;
      if (label != null) badge = BoardBadge(square: lastMove.to, label: label, spokenMove: moveText);
    }

    // The engine's best move in the shown position.
    BoardArrow? arrow;
    if (_showArrow && !data.gameOverAt(ply)) {
      final top = data.topLineAt(ply);
      final best = top == null || top.pv.isEmpty ? null : legalUci(position, top.pv.first);
      if (best != null) {
        final d = displaySquares(position, best);
        if (d.from != d.to) arrow = BoardArrow(from: d.from, to: d.to);
      }
    }

    final sideName = orientation == Side.white ? l10n.sideWhite : l10n.sideBlack;
    final what = moveText == null
        ? l10n.boardSemanticsStart
        : (badge == null
              ? l10n.boardSemanticsAfter(moveText)
              : l10n.boardSemanticsAfterLabel(moveText, labelName(l10n, badge.label)));
    final boardLabel = l10n.boardSemanticsView(what, sideName);

    Widget strip(Side side) => PlayerStrip(
          side: side,
          name: side == Side.white ? data.record.white : data.record.black,
          elo: side == Side.white ? data.record.whiteElo : data.record.blackElo,
          clockMs: clockAt(data.game, side, ply),
          isUser: data.userSide == side,
          toMove: position.turn == side && !data.gameOverAt(ply),
        );

    return CallbackShortcuts(
      bindings: {
        // Read the cursor, not the built `ply`: key repeat can outrun a rebuild.
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _goTo(cursor.ply - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _goTo(cursor.ply + 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _goTo(0),
        const SingleActivator(LogicalKeyboardKey.end): () => _goTo(cursor.length),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: EvalGauge(display: eval),
                    ),
                    strip(orientation.opposite),
                    LayoutBuilder(
                      builder: (context, c) => AnalysisBoard(
                        size: c.maxWidth,
                        fen: position.fen,
                        orientation: orientation,
                        lastMove: lastMove,
                        badge: badge,
                        arrow: arrow,
                        animate: _animate,
                        semanticsLabel: boardLabel,
                      ),
                    ),
                    strip(orientation),
                    // Above the text that changes height from move to move, so
                    // the graph stays put under the finger while scrubbing.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: EvalGraph(data: data, ply: ply, onSelect: _goTo),
                    ),
                    // Horizontal swipes below the board step through the game
                    // (SPEC F7).
                    GestureDetector(
                      key: const Key('swipe-area'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v < -150) _goTo(cursor.ply + 1);
                        if (v > 150) _goTo(cursor.ply - 1);
                      },
                      child: Column(
                        children: [
                          EngineLinesPanel(
                            data: data,
                            ply: ply,
                            expanded: _linesExpanded,
                            onToggle: () => setState(() => _linesExpanded = !_linesExpanded),
                          ),
                          CoachCard(line: coach, showExplain: ply > 0, gameId: data.record.id, ply: ply),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            MoveList(data: data, ply: ply, onSelect: _goTo),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, AppLocalizations l10n, BoardData data) {
    final cursor = _cursor!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              key: const Key('nav-first'),
              tooltip: l10n.boardFirstMove,
              onPressed: cursor.canBack ? () => _goTo(0) : null,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              key: const Key('nav-back'),
              tooltip: l10n.boardPreviousMove,
              onPressed: cursor.canBack ? () => _goTo(cursor.ply - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              key: const Key('nav-next'),
              tooltip: l10n.boardNextMove,
              onPressed: cursor.canForward ? () => _goTo(cursor.ply + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              key: const Key('nav-last'),
              tooltip: l10n.boardLastMove,
              onPressed: cursor.canForward ? () => _goTo(cursor.length) : null,
              icon: const Icon(Icons.last_page),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('open-key-moments'),
              tooltip: l10n.boardKeyMoments,
              onPressed: () => _openKeyMoments(data),
              icon: const Icon(Icons.flag_outlined),
            ),
            IconButton(
              key: const Key('open-report'),
              tooltip: l10n.boardReport,
              onPressed: () => _openReport(data),
              icon: const Icon(Icons.assessment_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

/// One choice of a dialog list: a button that is also a radio option for a
/// screen reader (checked + mutually exclusive group), with a visible tick.
class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({required this.optionKey, required this.onPressed, required this.text, required this.selected});

  final Key optionKey;
  final VoidCallback onPressed;
  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: SimpleDialogOption(
          key: optionKey,
          onPressed: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: Text(text)),
                if (selected) const ExcludeSemantics(child: Icon(Icons.check)),
              ],
            ),
          ),
        ),
      );
}
