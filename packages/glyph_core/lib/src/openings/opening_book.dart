import 'dart:isolate';

import '../game/game.dart';
import '../game/ply.dart';

/// One named opening position.
class OpeningEntry {
  const OpeningEntry(this.eco, this.name);

  final String eco;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is OpeningEntry && other.eco == eco && other.name == name;

  @override
  int get hashCode => Object.hash(eco, name);

  @override
  String toString() => '$eco $name';
}

/// How a game relates to the book.
class BookAnnotation {
  const BookAnnotation({
    required this.bookPlies,
    this.opening,
    this.openingPly,
  });

  /// No book at all (FEN start, Chess960 or an off-book first move).
  static const none = BookAnnotation(bookPlies: 0);

  /// Length of the contiguous book prefix: plies `1..bookPlies` are Book moves.
  final int bookPlies;

  /// Deepest named position reached anywhere in the game, if any.
  final OpeningEntry? opening;

  /// Ply of [opening].
  final int? openingPly;

  bool isBook(int ply) => ply >= 1 && ply <= bookPlies;
}

/// Opening names keyed by EPD (first four FEN fields), so transpositions are
/// recognised by position and not by move order (SPEC trap 7).
class OpeningBook {
  OpeningBook(Map<String, OpeningEntry> entries) : _entries = Map.unmodifiable(entries);

  /// Parses the `epd\teco\tname` asset. Blank and malformed lines are skipped.
  factory OpeningBook.parseTsv(String tsv) {
    final map = <String, OpeningEntry>{};
    for (final line in tsv.split('\n')) {
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length < 3) continue;
      map[f[0]] = OpeningEntry(f[1], f[2]);
    }
    return OpeningBook(map);
  }

  /// Parses [tsv] in a background isolate (the asset has ~3.9k rows).
  static Future<OpeningBook> parseTsvAsync(String tsv) =>
      Isolate.run(() => OpeningBook.parseTsv(tsv));

  final Map<String, OpeningEntry> _entries;

  int get length => _entries.length;

  /// Entry for an EPD (or a full FEN; only the first four fields are used).
  OpeningEntry? lookup(String epdOrFen) => _entries[epdOfFen(epdOrFen)];

  /// Book prefix and opening name of [game]. A game that does not start from
  /// the standard position (FEN start, Chess960) has no book.
  BookAnnotation annotate(Game game) {
    if (game.hasCustomStart || game.variant != GameVariant.standard) {
      return BookAnnotation.none;
    }
    var prefix = 0;
    var contiguous = true;
    OpeningEntry? opening;
    int? openingPly;
    for (final ply in game.plies) {
      final entry = _entries[ply.epd];
      if (entry == null) {
        contiguous = false;
        continue;
      }
      if (contiguous) prefix = ply.number;
      opening = entry;
      openingPly = ply.number;
    }
    return BookAnnotation(bookPlies: prefix, opening: opening, openingPly: openingPly);
  }
}
