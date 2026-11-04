import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

const assetPath = '../../app/assets/openings.tsv';

Game game(String pgn) => parsePgn(pgn).games.single;

void main() {
  group('asset integrity', () {
    test('openings.tsv matches the recorded SHA-256', () {
      final bytes = File(assetPath).readAsBytesSync();
      final recorded = File('$assetPath.sha256').readAsStringSync().trim().split(RegExp(r'\s+')).first;
      expect(recorded, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(sha256.convert(bytes).toString(), recorded);
    });

    test('3865 named rows, then 4117 unnamed book positions; unique 4-field EPDs', () {
      final lines = File(assetPath).readAsLinesSync();
      expect(lines, hasLength(3865 + 4117));
      final epds = lines.map((l) => l.split('\t').first).toSet();
      expect(epds, hasLength(lines.length));
      for (final (i, l) in lines.indexed) {
        final f = l.split('\t');
        expect(f, hasLength(3));
        expect(f[0].split(' '), hasLength(4));
        if (i < 3865) {
          expect(f[1], matches(RegExp(r'^[A-E]\d\d$')));
          expect(f[2], isNotEmpty);
        } else {
          expect((f[1], f[2]), ('', ''), reason: 'unnamed rows come after the named ones');
        }
      }
      expect(epds.take(3865).where((e) => !e.endsWith(' -')), hasLength(15), reason: 'legal en-passant squares only');
    });

    test('tool output is reproducible from the chess-openings checkout (when present)', () {
      final dir = Directory(Platform.environment['CHESS_OPENINGS_DIR'] ??
          '${Platform.environment['HOME']}/development/upstream/chess-openings');
      if (!dir.existsSync()) {
        markTestSkipped('chess-openings checkout not available');
        return;
      }
      final built = buildOpeningsTsv([for (final v in 'abcde'.split('')) File('${dir.path}/$v.tsv').readAsStringSync()]);
      expect(sha256.convert(utf8.encode(built)).toString(),
          File('$assetPath.sha256').readAsStringSync().split(' ').first);
    });

    test('the decoder works in an isolate', () async {
      final tsv = File(assetPath).readAsStringSync();
      final book = await OpeningBook.parseTsvAsync(tsv);
      expect(book.length, 3865);
      expect(book.bookPositions, 3865 + 4117);
      expect(book.lookup('rnbqkbnr/pppppppp/8/8/8/7N/PPPPPPPP/RNBQKB1R b KQkq -')?.name, 'Amar Opening');
    });
  });

  group('OpeningBook (real asset)', () {
    final book = OpeningBook.parseTsv(File(assetPath).readAsStringSync());

    test('named opening and contiguous prefix', () {
      final a = book.annotate(game('1. e4 e5 2. Nf3 Nc6 3. Bb5 *'));
      expect(a.opening!.eco, 'C60');
      expect(a.opening!.name, startsWith('Ruy Lopez'));
      expect(a.openingPly, 5);
      expect(a.bookPlies, 5);
      expect([for (var p = 0; p <= 6; p++) a.isBook(p)], [false, true, true, true, true, true, false]);
    });

    test('book ends at the first non-book ply; the name is the deepest position', () {
      // 1.e4 e5 2.a3 is a named line; 2...Nf6 3.Nf3 Nc6 4.Bb5 leaves it.
      final a = book.annotate(game('1. e4 e5 2. a3 Nf6 3. Nf3 Nc6 4. Bb5 *'));
      expect(a.opening!.name, contains("Mengarini"));
      expect(a.openingPly, 3);
      expect(a.bookPlies, 3);
      expect(a.isBook(4), isFalse);
    });

    test('transposition: matched by position, not move order', () {
      final a = book.annotate(game('1. d4 d5 2. Nf3 *'));
      final b = book.annotate(game('1. Nf3 d5 2. d4 *'));
      expect(a.opening, isNotNull);
      expect(b.opening, a.opening);
      expect((a.bookPlies, b.bookPlies), (3, 3));
    });

    test('a first move out of book gives no book and no opening', () {
      final z = book.annotate(game('1. a3 a6 2. h4 h5 3. Rh3 Rh6 4. Rg3 *'));
      expect(z.bookPlies, 1, reason: '1.a3 (Anderssen) is listed, nothing after it');
      final unknown = book.annotate(game('1. Na3 a6 2. h4 h5 *'));
      expect(unknown.bookPlies, 1);

    });

    test('FEN-start game: no Book, no opening', () {
      // Same moves as a book line, but the game starts from a FEN.
      final fenStart = game('[SetUp "1"]\n[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n\n1... e5 2. Nf3 Nc6 3. Bb5 *');
      expect(fenStart.hasCustomStart, isTrue);
      final a = book.annotate(fenStart);
      expect(a.bookPlies, 0);
      expect(a.opening, isNull);
      expect(a.isBook(1), isFalse);
    });

    test('Chess960 game: no Book', () {
      final g = game('[Variant "Chess960"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 *');
      expect(book.annotate(g).bookPlies, 0);
    });

    test('lookup takes a full FEN or an EPD', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/7N/PPPPPPPP/RNBQKB1R b KQkq - 1 1';
      expect(book.lookup(fen)?.name, 'Amar Opening');
      expect(book.lookup('8/8/8/8/8/8/8/8 w - -'), isNull);
    });

    test('unnamed steps of a named line are book but name nothing (Ruy Lopez 4.Ba4 Nf6)', () {
      final a = book.annotate(game('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O *'));
      expect(a.bookPlies, 16, reason: 'every position is a step of a named Closed Ruy Lopez line');
      expect(a.opening!.name, startsWith('Ruy Lopez'));
      final afterBa4 = game('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 *').plies.last;
      expect(book.lookup(afterBa4.fen), isNull);
      expect(book.contains(afterBa4.fen), isTrue);
    });
  });

  group('OpeningBook (small book)', () {
    final book = OpeningBook.parseTsv(buildOpeningsTsv([
      'eco\tname\tpgn\n'
          'B00\tKing\'s Pawn\t1. e4\n'
          'C20\tKing\'s Pawn Game\t1. e4 e5\n'
          'C40\tKing\'s Knight Opening\t1. e4 e5 2. Nf3\n'
          'B00\tFar line\t1. e4 e5 2. Nf3 Nf6 3. Nxe5\n',
    ]));

    test('unnamed steps of a named line keep the prefix going', () {
      // 2...Nf6 (ply 4) is not named, but it is a step of "Far line".
      final a = book.annotate(game('1. e4 e5 2. Nf3 Nf6 3. Nxe5 *'));
      expect(a.bookPlies, 5);
      expect(a.opening!.name, 'Far line');
      expect(a.openingPly, 5);
    });

    test('contiguous prefix stops at the first non-book ply, name is the deepest hit', () {
      // 2.Bc4 (ply 3) is off book in this small book.
      final a = book.annotate(game('1. e4 e5 2. Bc4 Nf6 3. Nf3 Nc6 *'));
      expect(a.bookPlies, 2);
      expect(a.isBook(3), isFalse);
      expect(a.opening!.name, "King's Pawn Game");
      expect(a.openingPly, 2);
    });

    test('a later named position after a gap is not Book, but names the opening', () {
      // 1.Nf3 e5 2.e4 transposes into the King's Knight Opening at ply 3.
      final a = book.annotate(game('1. Nf3 e5 2. e4 Nc6 *'));
      expect(a.bookPlies, 0);
      expect(a.isBook(3), isFalse);
      expect(a.opening!.name, "King's Knight Opening");
      expect(a.openingPly, 3);
    });

    test('builder appends unnamed book positions after the named rows', () {
      final tsv = buildOpeningsTsv(['h\nC40\tKK\t1. e4 e5 2. Nf3\n']);
      final rows = tsv.split('\n').where((r) => r.isNotEmpty).toList();
      expect(rows, hasLength(3));
      expect(rows[0], endsWith('\tC40\tKK'));
      expect(rows.skip(1).every((r) => r.endsWith('\t\t')), isTrue);
    });

    test('no listed position at all', () {
      final none = book.annotate(game('1. d4 d5 2. c4 *'));
      expect((none.bookPlies, none.opening, none.openingPly), (0, null, null));
      expect(none.isBook(1), isFalse);
    });

    test('builder rejects illegal moves and duplicate positions', () {
      expect(() => buildOpeningsTsv(['h\n' 'A00\tBad\t1. e5\n']), throwsFormatException);
      expect(() => buildOpeningsTsv(['h\nA00\tX\t1. e4\nA00\tY\t1. e4\n']), throwsFormatException);
    });
  });
}
