import 'package:dartchess/dartchess.dart' show Side;

import 'score.dart';

/// One parsed `info` line that carries a score, before perspective is fixed.
class UciInfo {
  const UciInfo({
    required this.depth,
    required this.multipv,
    required this.score,
    required this.exact,
    required this.pv,
    this.seldepth,
    this.nodes,
  });

  final int depth;
  final int? seldepth;

  /// 1-based line index (`multipv`, 1 when absent).
  final int multipv;

  /// Side-to-move POV, as sent by the engine.
  final Score score;

  /// False for `lowerbound` / `upperbound` scores.
  final bool exact;

  /// Principal variation in the engine's UCI notation (Chess960 mode: castling
  /// is king-takes-rook, the same form dartchess uses).
  final List<String> pv;
  final int? nodes;
}

/// Parses a single UCI `info` line. Returns null for lines that are not
/// scored lines: `info string ...`, `info currmove ...`, `info depth N` without
/// a score, refutation / currline lines and anything that is not `info`.
UciInfo? parseUciInfoLine(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.first != 'info') return null;

  int? depth, seldepth, nodes;
  var multipv = 1;
  Score? score;
  var exact = true;
  var pv = const <String>[];

  var i = 1;
  while (i < tokens.length) {
    switch (tokens[i]) {
      case 'string':
        return null; // free text, e.g. "info string NNUE evaluation using ..."
      case 'currmove':
      case 'currmovenumber':
      case 'currline':
      case 'refutation':
        return null;
      case 'depth':
        depth = _int(tokens, i + 1);
        i += 2;
      case 'seldepth':
        seldepth = _int(tokens, i + 1);
        i += 2;
      case 'multipv':
        multipv = _int(tokens, i + 1) ?? 1;
        i += 2;
      case 'nodes':
        nodes = _int(tokens, i + 1);
        i += 2;
      case 'score':
        final kind = i + 1 < tokens.length ? tokens[i + 1] : '';
        final value = _int(tokens, i + 2);
        if (value == null) return null;
        score = switch (kind) {
          'cp' => Score.cp(value),
          'mate' => Score.mate(value),
          _ => null,
        };
        if (score == null) return null;
        i += 3;
      case 'lowerbound':
      case 'upperbound':
        exact = false;
        i++;
      case 'pv':
        pv = tokens.sublist(i + 1);
        i = tokens.length;
      default:
        i++;
    }
  }
  if (score == null || depth == null) return null;
  return UciInfo(
    depth: depth,
    seldepth: seldepth,
    multipv: multipv,
    score: score,
    exact: exact,
    pv: pv,
    nodes: nodes,
  );
}

int? _int(List<String> tokens, int index) => index < tokens.length ? int.tryParse(tokens[index]) : null;

/// One engine line of a finished search, scored from White's point of view.
class EngineLine {
  const EngineLine({
    required this.rank,
    required this.score,
    required this.depth,
    required this.pv,
    this.seldepth,
    this.nodes,
  });

  /// 1 = best line.
  final int rank;
  final WhiteScore score;
  final int depth;
  final int? seldepth;
  final List<String> pv;
  final int? nodes;
}

/// What a search produced, finalized on `bestmove`.
class UciSearchResult {
  const UciSearchResult({
    required this.lines,
    required this.bestMove,
    this.ponder,
    this.depth = 0,
  });

  /// One line per multipv rank at the highest completed depth, ordered by rank.
  final List<EngineLine> lines;

  /// Null for `bestmove (none)` (checkmate / stalemate: no legal move).
  final String? bestMove;
  final String? ponder;

  /// Depth of [lines] (0 when there are none).
  final int depth;

  bool get noMove => bestMove == null;
}

/// Turns the output of one search (`info ...` lines up to `bestmove`) into a
/// [UciSearchResult].
///
/// Rules (SPEC trap 4): `lowerbound` / `upperbound` scores are skipped; `info
/// currmove` and `info string` are ignored; lines of different `multipv` may
/// interleave; the last exact score per multipv rank is kept and the result is
/// taken at the highest depth at which every rank reported (the highest
/// *completed* depth); the result is finalized on `bestmove`. Scores are
/// converted to White POV here with [toWhitePov], using [sideToMove] (the side
/// to move in the searched position).
class UciParser {
  UciParser({required this.sideToMove});

  final Side sideToMove;

  // depth -> rank -> last exact info at that depth.
  final Map<int, Map<int, UciInfo>> _byDepth = {};

  /// Feeds one engine output line. Returns the result when [line] is
  /// `bestmove ...`, and resets for the next search; null otherwise.
  UciSearchResult? feed(String line) {
    final trimmed = line.trim();
    if (trimmed.startsWith('bestmove')) return _finish(trimmed);
    if (trimmed.startsWith('info')) {
      final info = parseUciInfoLine(trimmed);
      if (info != null && info.exact) {
        (_byDepth[info.depth] ??= {})[info.multipv] = info;
      }
    }
    return null;
  }

  /// Discards partial state (a new search starts).
  void reset() => _byDepth.clear();

  UciSearchResult _finish(String bestmoveLine) {
    final tokens = bestmoveLine.split(RegExp(r'\s+'));
    String? best = tokens.length > 1 ? tokens[1] : null;
    if (best == '(none)' || best == '0000') best = null;
    String? ponder;
    final p = tokens.indexOf('ponder');
    if (p >= 0 && p + 1 < tokens.length) ponder = tokens[p + 1];

    final lines = <EngineLine>[];
    var depth = 0;
    if (_byDepth.isNotEmpty) {
      var expected = 0;
      for (final ranks in _byDepth.values) {
        if (ranks.length > expected) expected = ranks.length;
      }
      final depths = _byDepth.keys.toList()..sort((a, b) => b.compareTo(a));
      depth = depths.firstWhere((d) => _byDepth[d]!.length == expected, orElse: () => depths.first);
      final ranks = _byDepth[depth]!;
      for (final rank in ranks.keys.toList()..sort()) {
        final info = ranks[rank]!;
        lines.add(EngineLine(
          rank: rank,
          score: toWhitePov(info.score, sideToMove),
          depth: info.depth,
          seldepth: info.seldepth,
          pv: info.pv,
          nodes: info.nodes,
        ));
      }
    }
    _byDepth.clear();
    return UciSearchResult(lines: lines, bestMove: best, ponder: ponder, depth: depth);
  }
}
