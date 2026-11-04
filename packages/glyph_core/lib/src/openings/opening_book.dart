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

/// Opening positions keyed by EPD (first four FEN fields), so transpositions
/// are recognised by position and not by move order (SPEC trap 7).
///
/// The asset holds two kinds of rows: **named** positions (`epd\teco\tname`,
/// the chess-openings entries) and **unnamed book positions** (`epd\t\t`, the
/// steps on the way to a named position). Both count as book for the Book
/// label; only named ones name the opening.
class OpeningBook {
  OpeningBook(Map<String, OpeningEntry> entries, {Set<String> unnamed = const {}})
      : _entries = Map.unmodifiable(entries),
        _unnamed = Set.unmodifiable(unnamed);

  /// Parses the `epd\teco\tname` asset. Blank and malformed lines are skipped;
  /// a row with an empty name is an unnamed book position.
  factory OpeningBook.parseTsv(String tsv) {
    final map = <String, OpeningEntry>{};
    final unnamed = <String>{};
    for (final line in tsv.split('\n')) {
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length < 3 || f[0].isEmpty) continue;
      if (f[2].isEmpty) {
        unnamed.add(f[0]);
      } else {
        map[f[0]] = OpeningEntry(f[1], f[2]);
      }
    }
    unnamed.removeAll(map.keys);
    return OpeningBook(map, unnamed: unnamed);
  }

  /// Parses [tsv] in a background isolate (the asset has ~9k rows).
  static Future<OpeningBook> parseTsvAsync(String tsv) =>
      Isolate.run(() => OpeningBook.parseTsv(tsv));

  final Map<String, OpeningEntry> _entries;
  final Set<String> _unnamed;

  /// Number of named positions.
  int get length => _entries.length;

  /// Number of book positions (named plus unnamed).
  int get bookPositions => _entries.length + _unnamed.length;

  /// Named entry for an EPD (or a full FEN; only the first four fields are
  /// used). Null for unnamed book positions.
  OpeningEntry? lookup(String epdOrFen) => _entries[epdOfFen(epdOrFen)];

  /// Whether the position is a book position (named or not).
  bool contains(String epdOrFen) {
    final epd = epdOfFen(epdOrFen);
    return _entries.containsKey(epd) || _unnamed.contains(epd);
  }

  /// Book prefix and opening name of [game]. A game that does not start from
  /// the standard position (FEN start, Chess960) has no book.
  ///
  /// The prefix is contiguous: it ends at the first ply whose position is not
  /// a book position (later book positions are not Book moves). The opening
  /// is the deepest **named** position anywhere in the game.
  BookAnnotation annotate(Game game) {
    if (game.hasCustomStart || game.variant != GameVariant.standard) {
      return BookAnnotation.none;
    }
    var prefix = 0;
    var contiguous = true;
    OpeningEntry? opening;
    int? openingPly;
    for (final ply in game.plies) {
      final epd = ply.epd;
      final entry = _entries[epd];
      final inBook = entry != null || _unnamed.contains(epd);
      if (!inBook) contiguous = false;
      if (contiguous) prefix = ply.number;
      if (entry != null) {
        opening = entry;
        openingPly = ply.number;
      }
    }
    return BookAnnotation(bookPlies: prefix, opening: opening, openingPly: openingPly);
  }
}
