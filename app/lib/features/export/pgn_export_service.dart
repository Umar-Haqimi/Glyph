import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../board/board_data.dart';

/// An annotated PGN ready to share.
class ExportedPgn {
  const ExportedPgn({required this.pgn, required this.fileName});

  final String pgn;

  /// Sanitised: only `A-Za-z0-9._-`, `.pgn`.
  final String fileName;
}

/// Builds the annotated PGN of a stored game (SPEC F18): the original headers,
/// `[%eval]` and `[%clk]` per move, the NAG of each Brilliant / Great /
/// Inaccuracy / Mistake / Miss / Blunder, `[Annotator "Glyph"]`.
///
/// The labels and evaluations are what the board shows: stored labels for a
/// finished analysis, otherwise the in-memory classification of the positions
/// analysed so far (the same code as the board). A game that was never
/// analysed exports with its own `[%eval]` / `[%clk]` comments only.
class PgnExportService {
  PgnExportService(this._ref);

  final Ref _ref;

  /// Null when the game is gone or its stored PGN cannot be read.
  Future<ExportedPgn?> build(int gameId) async {
    final record = await _ref.read(gameRepositoryProvider).get(gameId);
    if (record == null) return null;
    final parsed = await parsePgnAsync(record.pgn);
    if (parsed.games.isEmpty) return null;
    final game = parsed.games.first;

    OpeningBook? book;
    try {
      book = await _ref.read(openingBookProvider.future);
    } catch (_) {
      book = null;
    }
    final analyses = _ref.read(analysisRepositoryProvider);
    final rows = await analyses.positionLines(gameId);
    final stored = record.analysisStatus == AnalysisStatus.completed ? await analyses.labels(gameId) : const <MoveLabelRecord>[];
    final data = BoardData.build(record: record, game: game, rows: rows, storedLabels: stored, book: book);

    final labels = <int, MoveLabel>{};
    for (var ply = 1; ply <= game.plyCount; ply++) {
      final label = data.moveAt(ply)?.label;
      if (label != null) labels[ply] = label;
    }
    final evals = <int, PlyEval>{};
    for (var ply = 1; ply <= game.plyCount; ply++) {
      final lines = data.lines[ply];
      if (lines == null || lines.isEmpty) continue; // not analysed, or the game ended here
      final score = lines.first.score;
      if (score.cp != null) {
        evals[ply] = PlyEval.cp(score.cp!);
      } else if (score.mate != null && score.mate != 0) {
        evals[ply] = PlyEval.mate(score.mate!);
      }
    }
    return ExportedPgn(
      pgn: exportAnnotatedPgn(game, labels: labels, evals: evals),
      fileName: exportFileName(game),
    );
  }
}

final pgnExportServiceProvider = Provider<PgnExportService>(PgnExportService.new);
