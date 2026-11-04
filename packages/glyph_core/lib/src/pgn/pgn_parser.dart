import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';

import '../game/game.dart';
import '../game/ply.dart';
import '../util/limits.dart';
import 'pgn_result.dart';
import 'pgn_splitter.dart';
import 'pgn_text.dart';

/// Inputs larger than this are parsed in a background isolate by the `*Async`
/// functions (SPEC 5.3).
const int isolateThresholdBytes = 100 * 1024;

const Set<String> _chess960Names = {
  'chess960',
  'chess 960',
  'fischerandom',
  'fischerrandom',
  'fischer random',
};

/// Parses PGN text: any number of games, mainline only, every move replayed.
///
/// Never throws. See [PgnParseResult].
PgnParseResult parsePgn(String input) {
  if (utf8Length(input) > Limits.maxPgnBytes) {
    return const PgnFailed([PgnIssue(PgnIssueKind.tooLarge)]);
  }
  final split = splitPgn(normalizePgnText(input));
  final games = <Game>[];
  final skipped = <PgnIssue>[];
  for (var i = 0; i < split.chunks.length; i++) {
    final (game, issue) = _buildGame(split.chunks[i], i);
    if (game != null) games.add(game);
    if (issue != null) skipped.add(issue);
  }
  if (split.truncated) skipped.add(const PgnIssue(PgnIssueKind.tooManyGames));
  if (games.isEmpty) {
    return PgnFailed(
      skipped.isEmpty ? const [PgnIssue(PgnIssueKind.noGames)] : skipped,
    );
  }
  return skipped.isEmpty ? PgnOk(games) : PgnPartial(games, skipped);
}

/// Decodes UTF-8 (malformed bytes become U+FFFD) and calls [parsePgn]. Rejects
/// more than 2 MB before decoding.
PgnParseResult parsePgnBytes(Uint8List bytes) {
  if (bytes.length > Limits.maxPgnBytes) {
    return const PgnFailed([PgnIssue(PgnIssueKind.tooLarge)]);
  }
  return parsePgn(utf8.decode(bytes, allowMalformed: true));
}

/// Like [parsePgn], but inputs over [isolateThresholdBytes] run in an isolate.
Future<PgnParseResult> parsePgnAsync(String input) async {
  if (input.length <= isolateThresholdBytes) return parsePgn(input);
  return Isolate.run(() => parsePgn(input));
}

/// Like [parsePgnBytes], but large inputs (decode included) run in an isolate.
Future<PgnParseResult> parsePgnBytesAsync(Uint8List bytes) async {
  if (bytes.length <= isolateThresholdBytes) return parsePgnBytes(bytes);
  return Isolate.run(() => parsePgnBytes(bytes));
}

final RegExp _trailingResult = RegExp(r'(1-0|0-1|1/2-1/2|\*)\s*$');
const Set<String> _results = {'1-0', '0-1', '1/2-1/2', '*'};

String _variantDisplayName(Rule rule) => switch (rule) {
      Rule.chess => 'Chess',
      Rule.antichess => 'Antichess',
      Rule.kingofthehill => 'King of the Hill',
      Rule.threecheck => 'Three-check',
      Rule.atomic => 'Atomic',
      Rule.horde => 'Horde',
      Rule.racingKings => 'Racing Kings',
      Rule.crazyhouse => 'Crazyhouse',
    };

(Game?, PgnIssue?) _buildGame(String chunk, int sourceIndex) {
  final gameIndex = sourceIndex + 1;
  try {
    final parsed = PgnGame.parsePgn(chunk, initHeaders: PgnGame.emptyHeaders);
    final headers = parsed.headers;

    // --- variant ---
    var variant = GameVariant.standard;
    final variantTag = headers['Variant']?.trim();
    if (variantTag != null && variantTag.isNotEmpty) {
      if (_chess960Names.contains(variantTag.toLowerCase())) {
        variant = GameVariant.chess960;
      } else {
        final rule = Rule.fromPgn(variantTag);
        if (rule != Rule.chess) {
          return (
            null,
            PgnIssue(
              PgnIssueKind.unsupportedVariant,
              gameIndex: gameIndex,
              variant: rule == null ? variantTag : _variantDisplayName(rule),
            ),
          );
        }
      }
    }

    // --- start position ---
    Position position = Chess.initial;
    var startFen = kInitialFEN;
    final fenTag = headers['FEN']?.trim();
    final setUp = headers['SetUp']?.trim();
    if (fenTag != null && fenTag.isNotEmpty && setUp != '0') {
      try {
        position = Position.setupPosition(
          Rule.chess,
          Setup.parseFen(fenTag),
          ignoreImpossibleCheck: true,
        );
        startFen = position.fen;
      } catch (_) {
        return (
          null,
          PgnIssue(PgnIssueKind.invalidFen, gameIndex: gameIndex),
        );
      }
    }

    // --- replay the mainline ---
    final plies = <Ply>[];
    for (final node in parsed.moves.mainline()) {
      final number = plies.length + 1;
      final fullmove = _fullmove(startFen, number);
      final black = _isBlackPly(startFen, number);
      if (number > Limits.maxPliesPerGame) {
        return (
          null,
          PgnIssue(
            PgnIssueKind.tooManyPlies,
            gameIndex: gameIndex,
            ply: number,
            moveNumber: fullmove,
            isBlackMove: black,
          ),
        );
      }
      final move = position.parseSan(node.san);
      if (move == null) {
        return (
          null,
          PgnIssue(
            PgnIssueKind.illegalMove,
            gameIndex: gameIndex,
            ply: number,
            san: node.san,
            moveNumber: fullmove,
            isBlackMove: black,
          ),
        );
      }
      final (next, san) = position.makeSan(move);

      int? clockMs;
      PlyEval? eval;
      final texts = <String>[];
      for (final raw in [...?node.startingComments, ...?node.comments]) {
        final c = PgnComment.fromPgn(raw);
        if (c.clock != null) clockMs = c.clock!.inMilliseconds;
        final e = c.eval;
        if (e != null) {
          if (e.mate != null && !e.isPawns()) {
            eval = PlyEval.mate(e.mate!);
          } else if (e.pawns != null) {
            eval = PlyEval.cp((e.pawns! * 100).round());
          }
        }
        if (c.text != null) texts.add(c.text!);
      }
      plies.add(
        Ply(
          number: number,
          san: san,
          uci: move.uci,
          fen: next.fen,
          clockMs: clockMs,
          eval: eval,
          comment: texts.isEmpty
              ? null
              : truncateUtf8(texts.join(' '), Limits.maxCommentBytes),
        ),
      );
      position = next;
    }
    if (plies.isEmpty) {
      return (null, PgnIssue(PgnIssueKind.noMoves, gameIndex: gameIndex));
    }

    var result = headers['Result']?.trim() ?? '';
    if (!_results.contains(result)) {
      result = _trailingResult.firstMatch(chunk)?.group(1) ?? '*';
    }
    return (
      Game(
        headers: headers,
        startFen: startFen,
        variant: variant,
        plies: plies,
        result: result,
        pgn: chunk,
        sourceIndex: sourceIndex,
      ),
      null,
    );
  } catch (_) {
    // dartchess should not throw on a replayed, validated game; treat anything
    // unexpected as an unreadable game rather than crashing the import.
    return (null, PgnIssue(PgnIssueKind.noMoves, gameIndex: gameIndex));
  }
}

bool _isBlackPly(String startFen, int number) {
  final startBlack = startFen.split(' ').elementAtOrNull(1) == 'b';
  return startBlack ? number.isOdd : number.isEven;
}

int _fullmove(String startFen, int number) {
  final parts = startFen.split(' ');
  final start = parts.length >= 6 ? int.tryParse(parts[5]) ?? 1 : 1;
  final startBlack = parts.elementAtOrNull(1) == 'b';
  final offset = startBlack ? number : number - 1; // plies since the start of move `start`
  return start + (offset ~/ 2);
}
