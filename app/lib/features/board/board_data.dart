import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../engine/engine_providers.dart';

/// Everything the analysis board and the report show about one game: the
/// parsed game, the stored engine lines, the move labels and the Win% series.
///
/// ### Where the labels come from
/// * Analysis `completed` and every ply has a stored label: the persisted
///   labels of M4 (`move_labels`), so opening a finished game costs nothing.
/// * Anything else (analysis running, cancelled, paused, or the review has
///   not been stored yet): [provisional] labels, computed **in memory** with
///   the M4 classifier from the lines stored so far and never persisted. A
///   move is labelled as soon as the engine data it needs exists (its own
///   position, plus the next one unless it is the engine's top two choices),
///   and the label is the same one the final classification will give, so
///   badges appear while the analysis runs and never change afterwards.
class BoardData {
  BoardData._({
    required this.record,
    required this.game,
    required this.lines,
    required this.wins,
    required this.moves,
    required this.book,
    required this.provisional,
  }) : keyMoments = KeyMoments.of(moves);

  /// Builds the data from the stored rows. Pure; the provider only loads.
  factory BoardData.build({
    required GameRecord record,
    required Game game,
    required List<PositionLineRecord> rows,
    required List<MoveLabelRecord> storedLabels,
    OpeningBook? book,
  }) {
    final lines = <int, List<EngineLine>>{};
    for (final row in rows) {
      final line = engineLineFromStored(
        rank: row.rank,
        scoreCp: row.scoreCp,
        scoreMate: row.scoreMate,
        depth: row.depth,
        pvUci: row.pvUci,
      );
      (lines[row.ply] ??= []).addAll([?line]);
    }
    final uci = [for (final p in game.plies) p.uci];
    final wins = Classifier.positionWins(game.startFen, uci, lines);
    final annotation = book?.annotate(game) ?? BookAnnotation.none;

    final useStored = record.analysisStatus == AnalysisStatus.completed && storedLabels.length >= game.plyCount;
    final List<ClassifiedMove?> moves;
    if (useStored) {
      final byPly = {for (final l in storedLabels) l.ply: l};
      moves = [
        for (var ply = 1; ply <= game.plyCount; ply++)
          if (byPly[ply] case final l?)
            ClassifiedMove(
              ply: ply,
              side: wins[ply - 1].position.turn,
              uci: game.plies[ply - 1].uci,
              label: l.label,
              epLoss: l.epLoss,
              winBefore: l.winBefore,
              winAfter: l.winAfter,
              bestUci: l.bestUci,
            )
          else
            null,
      ];
    } else {
      moves = const Classifier().classify(
        startFen: game.startFen,
        moves: uci,
        lines: lines,
        bookPlies: annotation.bookPlies,
      );
    }
    return BoardData._(
      record: record,
      game: game,
      lines: lines,
      wins: wins,
      moves: moves,
      book: annotation,
      provisional: !useStored,
    );
  }

  final GameRecord record;
  final Game game;

  /// Engine lines per position (0 = start), White POV, rank 1 first. A
  /// position without an entry has not been analysed yet; a terminal position
  /// has an empty list.
  final Map<int, List<EngineLine>> lines;

  /// Per-position Win% (White POV, `plyCount + 1` entries).
  final List<PositionWin> wins;

  /// One entry per ply (index 0 = ply 1); null while the engine data is
  /// missing.
  final List<ClassifiedMove?> moves;
  final BookAnnotation book;

  /// True when the labels were computed in memory (not read from storage).
  final bool provisional;

  /// Brilliant, Great, Miss, Mistake and Blunder moves, both sides, in order.
  final List<KeyMoment> keyMoments;

  int get plyCount => game.plyCount;

  /// The analysis finished and was stored.
  bool get analysisComplete => record.analysisStatus == AnalysisStatus.completed;

  ClassifiedMove? moveAt(int ply) => ply >= 1 && ply <= plyCount ? moves[ply - 1] : null;

  Ply? plyAt(int ply) => ply >= 1 && ply <= plyCount ? game.plies[ply - 1] : null;

  Position positionAt(int ply) => wins[ply.clamp(0, plyCount)].position;

  /// The position before ply [ply] is played.
  Position positionBefore(int ply) => positionAt(ply - 1);

  /// Engine lines of position [ply]; null = not analysed yet.
  List<EngineLine>? linesAt(int ply) => lines[ply];

  EngineLine? topLineAt(int ply) {
    for (final l in lines[ply] ?? const <EngineLine>[]) {
      if (l.rank == 1) return l;
    }
    return null;
  }

  /// Terminal state of position [ply] (checkmate, stalemate, insufficient
  /// material), whether or not the engine has reached it.
  Terminal? terminalAt(int ply) => wins[ply.clamp(0, plyCount)].terminal;

  /// White's Win% in position [ply], null when it is not known yet.
  double? whiteWinAt(int ply) => wins[ply.clamp(0, plyCount)].whiteWin;

  /// True when position [ply] has been analysed (or needs no analysis).
  bool analysedAt(int ply) => lines.containsKey(ply) || terminalAt(ply) != null;

  /// Positions with engine data (the start position counts).
  int get analysedPositions => [for (var p = 0; p <= plyCount; p++) if (lines.containsKey(p)) p].length;

  /// Who made ply [ply].
  Side moverAt(int ply) => positionBefore(ply).turn;

  /// Label count per side for the report card. Unlabelled moves are not
  /// counted.
  Map<MoveLabel, int> counts(Side side) {
    final out = {for (final l in MoveLabel.values) l: 0};
    for (final m in moves) {
      if (m != null && m.side == side) out[m.label] = out[m.label]! + 1;
    }
    return out;
  }

  /// The side the user played, from the game record (detected at import or
  /// set by hand).
  Side? get userSide => record.userSide;
}

/// The parsed game for the board. Parsed once per game (the PGN of a stored
/// game never changes); null when it cannot be read.
final parsedGameProvider = FutureProvider.autoDispose.family<Game?, int>((ref, id) async {
  final record = await ref.watch(gameRepositoryProvider).get(id);
  if (record == null) return null;
  final parsed = await parsePgnAsync(record.pgn);
  return parsed.games.isEmpty ? null : parsed.games.first;
});

/// [BoardData] of game [id], rebuilt when the stored game changes and after
/// every position the running analysis finishes (progressive badges).
final boardDataProvider = FutureProvider.autoDispose.family<BoardData?, int>((ref, id) async {
  // One tick per persisted position of this game's job: the pipeline writes a
  // position before it reports it, so a reload sees at least that many.
  ref.watch(analysisJobProvider.select((s) => s.gameId == id ? (s.runtimeType, s.completed) : null));
  final record = await ref.watch(gameProvider(id).future);
  final game = await ref.watch(parsedGameProvider(id).future);
  if (record == null || game == null) return null;
  final analyses = ref.watch(analysisRepositoryProvider);
  final rows = await analyses.positionLines(id);
  final labels = record.analysisStatus == AnalysisStatus.completed ? await analyses.labels(id) : const <MoveLabelRecord>[];
  OpeningBook? book;
  try {
    book = await ref.watch(openingBookProvider.future);
  } catch (_) {
    book = null;
  }
  return BoardData.build(record: record, game: game, rows: rows, storedLabels: labels, book: book);
});
