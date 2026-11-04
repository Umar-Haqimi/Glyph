import 'package:dartchess/dartchess.dart';

import 'game.dart';

/// Which side the user played, from the configured account names.
///
/// Matches the White/Black headers case-insensitively. When the `Site` tag
/// identifies lichess or chess.com only that site's username is considered;
/// otherwise both are. Returns null when neither or both sides match.
Side? detectUserSide(
  Game game, {
  String? lichessUsername,
  String? chessComUsername,
}) {
  final site = (game.site ?? '').toLowerCase();
  final names = <String>{};
  void add(String? n) {
    final t = n?.trim().toLowerCase();
    if (t != null && t.isNotEmpty) names.add(t);
  }

  final isLichess = site.contains('lichess');
  final isChessCom = site.contains('chess.com');
  if (isLichess || !isChessCom) add(lichessUsername);
  if (isChessCom || !isLichess) add(chessComUsername);
  if (names.isEmpty) return null;

  final w = names.contains(game.white?.toLowerCase());
  final b = names.contains(game.black?.toLowerCase());
  if (w == b) return null;
  return w ? Side.white : Side.black;
}
