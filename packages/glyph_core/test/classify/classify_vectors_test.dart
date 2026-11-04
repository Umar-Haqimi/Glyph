import 'dart:convert';
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';

/// One case of `test/vectors/classify/*.json` (SPEC 7.1 item 4):
/// `{name, transcript, startFen, moves, ply, expectedLabel, note}` plus the
/// optional `book` (false: classify without the opening book, to test the
/// engine rules on theory moves), `variant`, `epLoss` (exact expected loss)
/// and `sacrifice` (expected SEE sacrifice flag).
class ClassifyVector {
  ClassifyVector(this.file, Map<String, dynamic> j)
      : name = j['name'] as String,
        transcript = j['transcript'] as String,
        startFen = j['startFen'] as String,
        san = (j['moves'] as String).split(' '),
        ply = j['ply'] as int,
        expected = MoveLabel.values.byName(j['expectedLabel'] as String),
        note = j['note'] as String,
        useBook = j['book'] as bool? ?? true,
        variant = j['variant'] == 'chess960' ? GameVariant.chess960 : GameVariant.standard,
        epLoss = (j['epLoss'] as num?)?.toDouble(),
        sacrifice = j['sacrifice'] as bool?;

  final String file;
  final String name;
  final String transcript;
  final String startFen;
  final List<String> san;
  final int ply;
  final MoveLabel expected;
  final String note;
  final bool useBook;
  final GameVariant variant;
  final double? epLoss;
  final bool? sacrifice;
}

List<ClassifyVector> classifyVectors() {
  final files = Directory('test/vectors/classify').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      for (final j in jsonDecode(f.readAsStringSync()) as List) ClassifyVector(f.uri.pathSegments.last, j as Map<String, dynamic>),
  ];
}

void main() {
  final vectors = classifyVectors();
  final book = realOpeningBook();

  test('coverage: at least 3 cases per label (SPEC 7.1 item 4)', () {
    for (final label in MoveLabel.values) {
      expect(vectors.where((v) => v.expected == label), hasLength(greaterThanOrEqualTo(3)), reason: label.name);
    }
    expect(vectors.map((v) => v.name).toSet(), hasLength(vectors.length), reason: 'unique names');
  });

  for (final v in vectors) {
    test('${v.file}: ${v.name} -> ${v.expected.name}', () async {
      final moves = sanOrUciToUci(v.startFen, v.san);
      expect(moves, hasLength(v.ply), reason: 'moves run up to and including the classified ply');
      // The real pipeline over the recorded engine output, as the app stores it.
      final lines = await analyseFromTranscript(v.transcript, startFen: v.startFen, moves: moves);
      final game = gameFrom(v.startFen, moves, variant: v.variant);
      final review = reviewGame(game, lines, book: v.useBook ? book : null);
      final m = review.moves[v.ply - 1]!;
      expect(m.label, v.expected, reason: '${v.note}\n$m');
      if (v.epLoss != null) expect(m.epLoss, v.epLoss, reason: 'exact loss');
      if (v.sacrifice != null) expect(m.sacrifice, v.sacrifice, reason: 'SEE sacrifice flag');
    });
  }
}
