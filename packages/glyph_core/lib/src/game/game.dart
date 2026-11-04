import 'package:dartchess/dartchess.dart';

import 'ply.dart';

enum GameVariant { standard, chess960 }

/// A parsed, replay-validated game (mainline only).
class Game {
  Game({
    required Map<String, String> headers,
    required this.startFen,
    required this.variant,
    required List<Ply> plies,
    required this.result,
    required this.pgn,
    this.sourceIndex = 0,
  })  : headers = Map.unmodifiable(headers),
        plies = List.unmodifiable(plies);

  /// Headers in file order (missing tags stay missing; no defaults injected).
  final Map<String, String> headers;

  /// Full FEN of the start position (the standard one when there is no FEN tag).
  final String startFen;

  final GameVariant variant;
  final List<Ply> plies;

  /// `1-0`, `0-1`, `1/2-1/2` or `*`.
  final String result;

  /// This game's PGN text, newline-normalised and comment-sanitised.
  final String pgn;

  /// 0-based index of the game in the source text.
  final int sourceIndex;

  int get plyCount => plies.length;

  /// True when the game does not start from the standard position.
  bool get hasCustomStart => startFen != kInitialFEN;

  /// Side to move at the start position.
  Side get startSide => startFen.split(' ').elementAtOrNull(1) == 'b' ? Side.black : Side.white;

  String? get white => _clean(headers['White']);
  String? get black => _clean(headers['Black']);
  String? get event => _clean(headers['Event']);
  String? get site => _clean(headers['Site']);
  String? get timeControl => _clean(headers['TimeControl']);
  String? get eco => _clean(headers['ECO']);
  String? get openingHeader => _clean(headers['Opening']);
  int? get whiteElo => _elo(headers['WhiteElo']);
  int? get blackElo => _elo(headers['BlackElo']);

  /// `YYYY.MM.DD` from `Date`, falling back to `UTCDate`; null when unknown.
  String? get date {
    for (final key in const ['Date', 'UTCDate']) {
      final v = _clean(headers[key]);
      if (v != null && !v.startsWith('?')) return v;
    }
    return null;
  }

  /// The start position as a dartchess [Position].
  Position startPosition() => Position.setupPosition(
        Rule.chess,
        Setup.parseFen(startFen),
        ignoreImpossibleCheck: true,
      );

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty || t == '?' || t == '-' ? null : t;
  }

  static int? _elo(String? v) {
    if (v == null) return null;
    final n = int.tryParse(v.trim());
    return n == null || n <= 0 ? null : n;
  }
}
