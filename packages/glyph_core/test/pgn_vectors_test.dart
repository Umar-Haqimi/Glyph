import 'dart:io';
import 'dart:typed_data';

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/vectors/pgn/$name').readAsStringSync();
Uint8List fixtureBytes(String name) => File('test/vectors/pgn/$name').readAsBytesSync();

Game single(PgnParseResult r) {
  expect(r, isA<PgnOk>(), reason: '$r');
  expect(r.games, hasLength(1));
  return r.games.single;
}

void main() {
  group('real-world fixtures', () {
    test('chess.com download with %clk', () {
      final g = single(parsePgn(fixture('chesscom_download_clk.pgn')));
      expect(g.plyCount, 74);
      expect(g.white, 'BornForTheEndgame');
      expect(g.black, 'Hikaru');
      expect(g.whiteElo, 2899);
      expect(g.blackElo, 3467);
      expect(g.result, '0-1');
      expect(g.eco, 'E26');
      expect(g.timeControl, '180');
      expect(g.date, '2026.10.23');
      expect(g.plies.first.clockMs, 180000);
      expect(g.plies[3].clockMs, 179200); // 2... e6 {[%clk 0:02:59.2]}
      expect(g.plies.last.san, 'Re1#');
      expect(g.plies.last.clockMs, 42500);
      expect(g.plies.every((p) => p.eval == null), isTrue);
      expect(g.hasCustomStart, isFalse);
    });

    test('chess.com app share text: preamble dropped', () {
      final g = single(parsePgn(fixture('chesscom_app_share.pgn')));
      expect(g.white, 'Hikaru');
      expect(g.black, 'gurelediz');
      expect(g.plyCount, 78);
      expect(g.result, '1/2-1/2');
      expect(g.headers['Tournament'], contains('bullet-brawl'));
      expect(g.pgn, isNot(contains('Check out')));
      expect(g.plies.last.clockMs, 17600);
    });

    test('lichess API export with %eval, %clk and opening', () {
      final g = single(parsePgn(fixture('lichess_api_export.pgn')));
      expect(g.plyCount, 31);
      expect(g.eco, 'A01');
      expect(g.openingHeader, 'Nimzo-Larsen Attack');
      expect(g.plies[0].eval, const PlyEval.cp(0));
      expect(g.plies[1].eval, const PlyEval.cp(17));
      expect(g.plies[0].clockMs, 90000);
      expect(g.plies[25].san, 'Ne4');
      expect(g.plies[25].eval, const PlyEval.mate(3));
      expect(g.plies[30].san, 'Qxg7#');
      expect(g.plies[30].eval, isNull);
      expect(g.plies[30].clockMs, 79000);
      expect(g.headers['Variant'], 'Standard');
      expect(g.variant, GameVariant.standard);
    });

    test('lichess app share text (no comments)', () {
      final share = single(parsePgn(fixture('lichess_app_share.pgn')));
      final api = single(parsePgn(fixture('lichess_api_export.pgn')));
      expect(share.plies.map((p) => p.san), api.plies.map((p) => p.san));
      expect(share.plies.map((p) => p.fen), api.plies.map((p) => p.fen));
      expect(share.plies.every((p) => p.eval == null && p.clockMs == null), isTrue);
    });

    test('50-game file', () {
      final r = parsePgn(fixture('fifty_games.pgn'));
      expect(r, isA<PgnOk>());
      expect(r.games, hasLength(50));
      expect(r.games.map((g) => g.sourceIndex), List.generate(50, (i) => i));
      expect(r.games.first.white, 'Boris');
      expect(r.games.first.plyCount, 82);
      expect(r.games.every((g) => g.plyCount >= 20), isTrue);
    });

    test('games not separated by a blank line are not merged', () {
      final r = parsePgn(fixture('no_blank_lines.pgn'));
      expect(r.games, hasLength(3));
      final fifty = parsePgn(fixture('fifty_games.pgn')).games;
      for (var i = 0; i < 3; i++) {
        expect(r.games[i].plies.map((p) => p.san), fifty[i].plies.map((p) => p.san));
        expect(r.games[i].headers, fifty[i].headers);
      }
    });

    test('Chess960 with [SetUp][FEN] and castling', () {
      final g = single(parsePgn(fixture('chess960_fen.pgn')));
      expect(g.variant, GameVariant.chess960);
      expect(g.hasCustomStart, isTrue);
      expect(g.startFen, 'brnkqbnr/pppppppp/8/8/8/8/PPPPPPPP/BRNKQBNR w KQkq - 0 1');
      expect(g.plyCount, 49);
      final castle = g.plies[16]; // 9. O-O
      expect(castle.san, 'O-O');
      expect(castle.uci, 'd1h1', reason: 'dartchess: castling is king-takes-rook');
      expect(g.plies.last.eval, isNotNull);
    });

    test('CRLF + BOM (bytes and string)', () {
      final bytes = fixtureBytes('crlf_bom.pgn');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(String.fromCharCodes(bytes), contains('\r\n'));
      final g = single(parsePgnBytes(bytes));
      final api = single(parsePgn(fixture('lichess_api_export.pgn')));
      expect(g.plies.map((p) => p.san), api.plies.map((p) => p.san));
      expect(g.headers.keys.first, 'Event');
      expect(g.pgn, isNot(contains('\r')));
      expect(g.pgn, isNot(contains('﻿')));
      // Lone CR line endings too.
      final cr = single(parsePgn(fixture('lichess_api_export.pgn').replaceAll('\n', '\r')));
      expect(cr.plyCount, 31);
    });

    test('variations, NAGs and nested-brace comments: mainline only', () {
      final r = parsePgn(fixture('variations_nags_nested.pgn'));
      expect(r, isA<PgnOk>());
      expect(r.games, hasLength(2));
      final g = r.games.first;
      expect(g.plyCount, 33);
      expect(g.plies.take(5).map((p) => p.san), ['e4', 'e5', 'Nf3', 'd6', 'd4']);
      expect(g.plies.map((p) => p.san), isNot(contains('Nc6')));
      expect(g.plies[3].comment, 'A solid move, though (nested braces) are unusual in PGN.');
      expect(g.plies[30].eval, const PlyEval.mate(2));
      expect(g.plies[30].clockMs, 41500);
      expect(g.plies.last.san, 'Rd8#');
      expect(g.plies.last.comment, contains('inside a comment'));
      expect(g.plies.last.comment, contains('[Event "Not a game"]'));
      expect(g.result, '1-0');
      final g2 = r.games[1];
      expect(g2.white, 'Alice');
      expect(g2.plyCount, 4);
      expect(g2.result, '1/2-1/2');
    });

    test('illegal move: game, ply and SAN are reported', () {
      final single = parsePgn(fixture('illegal_move_single.pgn'));
      expect(single, isA<PgnFailed>());
      final i = (single as PgnFailed).issue;
      expect(i.kind, PgnIssueKind.illegalMove);
      expect((i.gameIndex, i.ply, i.san, i.moveNumber, i.isBlackMove), (1, 27, 'Nxe5', 14, false));
      expect(i.message, 'Game 1, move 14 (Nxe5): illegal move.');

      final multi = parsePgn(fixture('illegal_move_in_multi.pgn'));
      expect(multi, isA<PgnPartial>());
      expect(multi.games, hasLength(2));
      final skipped = (multi as PgnPartial).skipped.single;
      expect(skipped.message, 'Game 2, move 14 (Nxe5): illegal move.');
      expect(skipped.gameIndex, 2);
    });

    test('illegal Black move after a FEN start numbers moves from the FEN', () {
      const pgn = '''
[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 7"]
[SetUp "1"]

7... e5 8. Nf3 Ke6 9. Ke2 *
''';
      final i = (parsePgn(pgn) as PgnFailed).issue;
      expect((i.ply, i.san, i.moveNumber, i.isBlackMove), (3, 'Ke6', 8, true));
      expect(i.message, 'Game 1, move 8... (Ke6): illegal move.');
    });

    test('crazyhouse is rejected with a clear message', () {
      final r = parsePgn(fixture('crazyhouse.pgn'));
      expect(r, isA<PgnFailed>());
      final i = (r as PgnFailed).issue;
      expect(i.kind, PgnIssueKind.unsupportedVariant);
      expect(i.message, "Crazyhouse games aren't supported.");
      final mixed = parsePgn(fixture('crazyhouse_mixed.pgn'));
      expect(mixed, isA<PgnPartial>());
      expect(mixed.games, hasLength(2));
      expect((mixed as PgnPartial).skipped.single.gameIndex, 2);
    });

    test('other variants and unknown variant names', () {
      for (final (tag, shown) in [
        ('Atomic', 'Atomic'),
        ('Three-check', 'Three-check'),
        ('King of the Hill', 'King of the Hill'),
        ('Horde', 'Horde'),
        ('Racing Kings', 'Racing Kings'),
        ('Antichess', 'Antichess'),
        ('Dunsany', 'Dunsany'),
      ]) {
        final r = parsePgn('[Variant "$tag"]\n\n1. e4 e5 *\n') as PgnFailed;
        expect(r.issue.message, "$shown games aren't supported.");
      }
    });

    test('0-move game', () {
      final r = parsePgn(fixture('zero_moves.pgn'));
      expect(r, isA<PgnFailed>());
      expect((r as PgnFailed).issue.kind, PgnIssueKind.noMoves);
      expect(r.issue.message, 'Game 1, no moves.');
    });

    test('invalid FEN and empty input', () {
      final bad = parsePgn('[FEN "not a fen"]\n[SetUp "1"]\n\n1. e4 *\n') as PgnFailed;
      expect(bad.issue.kind, PgnIssueKind.invalidFen);
      for (final s in ['', '   \n\n', 'hello world', 'just some text without a game']) {
        expect((parsePgn(s) as PgnFailed).issue.kind, PgnIssueKind.noGames, reason: s);
      }
    });
  });

  group('DoS caps', () {
    const game = '[White "A"]\n[Black "B"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 1-0\n';

    test('2 MB + 1 byte is rejected, 2 MB is accepted', () {
      final over = game + ' ' * (Limits.maxPgnBytes + 1 - game.length);
      expect(over.length, Limits.maxPgnBytes + 1);
      final r = parsePgn(over);
      expect(r, isA<PgnFailed>());
      expect((r as PgnFailed).issue.kind, PgnIssueKind.tooLarge);
      expect(r.issue.message, 'This file is larger than 2 MB.');
      final at = game + ' ' * (Limits.maxPgnBytes - game.length);
      expect(parsePgn(at), isA<PgnOk>());
      // Bytes entry point, same boundary.
      final bytes = Uint8List(Limits.maxPgnBytes + 1)..fillRange(0, Limits.maxPgnBytes + 1, 0x20);
      bytes.setRange(0, game.length, game.codeUnits);
      expect((parsePgnBytes(bytes) as PgnFailed).issue.kind, PgnIssueKind.tooLarge);
      expect(parsePgnBytes(Uint8List.sublistView(bytes, 0, Limits.maxPgnBytes)), isA<PgnOk>());
    });

    test('the cap counts UTF-8 bytes, not characters', () {
      final tail = 'é' * (Limits.maxPgnBytes ~/ 2); // 2 bytes each, exactly 2 MB
      final okInput = '$game{$tail}';
      expect(okInput.length, lessThan(Limits.maxPgnBytes));
      expect((parsePgn(okInput.replaceFirst('{', ' ')) as PgnFailed).issue.kind,
          PgnIssueKind.tooLarge);
    });

    test('async API gives the same answer (isolate for > 100 KB)', () async {
      final text = fixture('fifty_games.pgn') * 3; // ~180 KB: runs in an isolate
      expect(text.length, greaterThan(isolateThresholdBytes));
      final sync = parsePgn(text);
      final async = await parsePgnAsync(text);
      expect(async.games, hasLength(150));
      expect(async.games.map((g) => g.plies.length), sync.games.map((g) => g.plies.length));
      expect(async.games.last.plies.last.fen, sync.games.last.plies.last.fen);
      final tooBig = await parsePgnBytesAsync(Uint8List(Limits.maxPgnBytes + 1));
      expect(tooBig, isA<PgnFailed>());
      final small = await parsePgnAsync(game);
      expect(small, isA<PgnOk>());
      final viaBytes = await parsePgnBytesAsync(
        Uint8List.fromList(fixture('fifty_games.pgn').codeUnits + fixture('fifty_games.pgn').codeUnits),
      );
      expect(viaBytes.games, hasLength(100));
    });

    String tiny(int n) => '[Event "g$n"]\n[Result "*"]\n\n1. e4 *\n';

    test('500 games listed, the 501st is dropped', () {
      final at = parsePgn(List.generate(Limits.maxGamesPerFile, tiny).join('\n'));
      expect(at, isA<PgnOk>());
      expect(at.games, hasLength(500));
      final over = parsePgn(List.generate(Limits.maxGamesPerFile + 1, tiny).join('\n'));
      expect(over, isA<PgnPartial>());
      expect(over.games, hasLength(500));
      expect((over as PgnPartial).skipped.single.kind, PgnIssueKind.tooManyGames);
      expect(over.games.last.headers['Event'], 'g499');
    });

    String shuffle(int plies) {
      final b = StringBuffer('[Result "*"]\n\n');
      for (var i = 0; i < plies ~/ 4; i++) {
        b.write('${2 * i + 1}. Nf3 Nf6 ${2 * i + 2}. Ng1 Ng8 ');
      }
      b.write('*');
      return b.toString();
    }

    test('1000 plies accepted, 1001 rejected', () {
      expect(single(parsePgn(shuffle(1000))).plyCount, 1000);
      final over = '${shuffle(1000).replaceAll(' *', '')} 501. Nf3 *';
      final r = parsePgn(over) as PgnFailed;
      expect(r.issue.kind, PgnIssueKind.tooManyPlies);
      expect(r.issue.ply, 1001);
    });

    test('comments are truncated to 4 KB (bytes) and keep clock/eval', () {
      final long = 'x' * 10000;
      final g = single(parsePgn('1. e4 {[%clk 0:05:00] $long} e5 {${'é' * 5000}} *'));
      expect(g.plies[0].comment!.length, lessThanOrEqualTo(Limits.maxCommentBytes));
      expect(g.plies[0].comment!.length, greaterThan(Limits.maxCommentBytes - 100));
      expect(g.plies[0].clockMs, 300000);
      expect(g.plies[1].comment!.length, Limits.maxCommentBytes ~/ 2);
      expect(g.plies[1].comment, isNot(contains('�')));
      final exact = single(parsePgn('1. e4 {${'y' * Limits.maxCommentBytes}} *'));
      expect(exact.plies[0].comment!.length, Limits.maxCommentBytes);
    });

    test('pathological unbalanced braces stay linear', () {
      final sw = Stopwatch()..start();
      final r = parsePgn('1. e4 ${'{{}' * 150000} e5 *');
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(r, isA<PgnOk>());
    });
  });

  group('splitter', () {
    test('headerless movetext, one and many games', () {
      expect(single(parsePgn('1. e4 e5 2. Nf3 Nc6 *')).plyCount, 4);
      final r = parsePgn('1. e4 e5 1-0 1. d4 d5 2. c4 0-1');
      expect(r.games.map((g) => g.plyCount), [2, 3]);
      expect(r.games.map((g) => g.result), ['1-0', '0-1']);
    });

    test('a game without a result token still ends at the next tag line', () {
      const pgn = '[Event "A"]\n\n1. e4 e5\n[Event "B"]\n\n1. d4 d5 *\n';
      final r = parsePgn(pgn);
      expect(r.games.map((g) => g.headers['Event']), ['A', 'B']);
      expect(r.games.first.result, '*');
    });

    test('result tokens inside variations and comments do not end a game', () {
      final g = single(parsePgn('1. e4 e5 (1... c5 1-0) { 0-1 } 2. Nf3 *'));
      expect(g.plyCount, 3);
    });

    test('brace inside a header value does not open a comment', () {
      final g = single(parsePgn('[Event "Odd {name"]\n[White "A"]\n\n1. e4 e5 *'));
      expect(g.headers['Event'], 'Odd {name');
      expect(g.plyCount, 2);
    });

    test('0-0 / 0-0-0 and null-ish junk are tolerated', () {
      final g = single(parsePgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 Nf6 5. d3 0-0 *'));
      expect(g.plies[6].san, 'O-O');
      expect(g.plies.last.san, 'O-O');
    });
  });

  group('splitter regressions (M2 review)', () {
    const game = '[Event "A"]\n[White "W"]\n\n1. e4 e5 2. Nf3 *\n';

    test('an unclosed variation does not swallow the following games', () {
      final r = parsePgn(
        '[Event "A"]\n\n1. e4 e5 (1... c5 2. Nf3 *\n\n[Event "B"]\n\n1. d4 d5 *\n\n[Event "C"]\n\n1. c4 *',
      );
      expect(r.games.map((g) => g.headers['Event']), ['A', 'B', 'C']);
      expect(r.games.map((g) => g.plyCount), [2, 2, 1]);
    });

    test('parentheses in a share-text preamble do not eat the headers', () {
      for (final preamble in [
        'Check out my game (vs Hikaru)!\nhttps://chess.com/game/live/1\n\n',
        'Check out my game (vs Hikaru!\n\n',
        'Look ) at this\n\n',
        'Analyze this (1-0) win\n\n',
      ]) {
        final g = single(parsePgn('$preamble$game'));
        expect(g.headers['Event'], 'A', reason: preamble);
        expect(g.white, 'W', reason: preamble);
        expect(g.plyCount, 3, reason: preamble);
      }
    });
  });

  group('round trip', () {
    const files = [
      'chesscom_download_clk.pgn',
      'chesscom_app_share.pgn',
      'lichess_api_export.pgn',
      'lichess_app_share.pgn',
      'chess960_fen.pgn',
      'crlf_bom.pgn',
      'variations_nags_nested.pgn',
      'fifty_games.pgn',
    ];
    for (final f in files) {
      test('$f: import -> export -> import is identical', () {
        final first = parsePgnBytes(fixtureBytes(f));
        expect(first.games, isNotEmpty);
        for (final g in first.games) {
          for (final annotator in [false, true]) {
            final out = exportAnnotatedPgn(g, annotator: annotator);
            final again = single(parsePgn(out));
            expect(again.plies.map((p) => (p.san, p.uci, p.fen, p.clockMs, p.eval)),
                g.plies.map((p) => (p.san, p.uci, p.fen, p.clockMs, p.eval)));
            final h = Map.of(again.headers);
            if (annotator) expect(h.remove('Annotator'), 'Glyph');
            expect(h, g.headers);
            expect(again.headers.keys.where((k) => k != 'Annotator').toList(), g.headers.keys.toList(),
                reason: 'header order');
            expect(again.result, g.result);
            expect(again.startFen, g.startFen);
            expect(again.variant, g.variant);
          }
        }
      });
    }
  });
}
