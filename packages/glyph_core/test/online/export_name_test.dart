import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeFileName', () {
    test('keeps A-Z a-z 0-9 . _ - and replaces the rest', () {
      expect(sanitizeFileName('Alice-99_x.y'), 'Alice-99_x.y');
      expect(sanitizeFileName('a b/c\\d:e*f?g"h<i>j|k'), 'a_b_c_d_e_f_g_h_i_j_k');
      expect(sanitizeFileName('Zoë 日本'), 'Zo');
    });

    test('paths, dot runs and control characters cannot survive', () {
      for (final raw in ['../../etc/passwd', '..\\..\\x', '/abs/path', 'a\u0000b', 'a\nb', '.hidden', '...', 'name.', '~/x', 'CON:', '%2e%2e/x']) {
        final s = sanitizeFileName(raw);
        expect(s, isNot(contains('/')), reason: raw);
        expect(s, isNot(contains('\\')), reason: raw);
        expect(s, isNot(contains('..')), reason: raw);
        expect(s, isNot(startsWith('.')), reason: raw);
        expect(s, matches(RegExp(r'^[A-Za-z0-9._-]+$')), reason: raw);
      }
      expect(sanitizeFileName('../../etc/passwd'), 'etc_passwd');
    });

    test('length cap and fallback', () {
      expect(sanitizeFileName('x' * 500).length, 80);
      expect(sanitizeFileName('x' * 500, maxLength: 10), 'x' * 10);
      expect(sanitizeFileName(''), 'game');
      expect(sanitizeFileName('???'), 'game');
      expect(sanitizeFileName('   ', fallback: 'none'), 'none');
    });
  });

  group('exportFileName', () {
    Game game(Map<String, String> headers) => (parsePgn(
              '${headers.entries.map((e) => '[${e.key} "${e.value}"]').join('\n')}\n\n1. e4 e5 *\n',
            ) as PgnOk)
        .games
        .single;

    test('white_vs_black_date.pgn', () {
      expect(exportFileName(game({'White': 'Alice', 'Black': 'Bob', 'Date': '2026.10.23'})), 'Alice_vs_Bob_2026-10-23.pgn');
    });

    test('unknown players and dates', () {
      expect(exportFileName(game({'White': '?', 'Black': '?', 'Date': '????.??.??'})), 'game.pgn');
      expect(exportFileName(game({'White': 'Alice', 'Black': '?'})), 'Alice_vs_unknown.pgn');
    });

    test('hostile names give a safe file name', () {
      final name = exportFileName(game({'White': '../../x/y', 'Black': 'a"b<c>', 'Date': '2026.01.01'}));
      expect(name, matches(RegExp(r'^[A-Za-z0-9._-]+\.pgn$')));
      expect(name, isNot(contains('..')));
      expect(name.length, lessThanOrEqualTo(75));
    });
  });
}
