import 'package:dartchess/dartchess.dart';

import '../engine/score.dart';

/// A score as the prompt shows it: from [side]'s point of view, `+0.3`,
/// `-2.1`, `0.0`, `#4` (side mates in 4) or `-#2` (side is mated in 2).
String formatScoreFor(WhiteScore score, Side side) {
  final mate = score.mate;
  if (mate != null) {
    if (mate == 0) return '#0';
    final forSide = (mate > 0) == (side == Side.white);
    return forSide ? '#${mate.abs()}' : '-#${mate.abs()}';
  }
  final cp = side == Side.white ? score.cp! : -score.cp!;
  final tenths = (cp.abs() / 100 * 10 + 0.5).floor();
  final text = '${tenths ~/ 10}.${tenths % 10}';
  if (tenths == 0) return text;
  return cp < 0 ? '-$text' : '+$text';
}

/// SAN of the moves of [uci] (dartchess UCI) played from [position]; stops at
/// the first move that is not legal, so a stale or garbled PV never throws.
List<String> sanLine(Position position, List<String> uci, {int maxMoves = 6}) {
  final out = <String>[];
  var pos = position;
  for (final u in uci.take(maxMoves)) {
    if (u.length < 4 || u.length > 5) break;
    final move = Move.parse(u);
    if (move == null || !pos.isLegal(move)) break;
    final (next, san) = pos.makeSan(move);
    out.add(san);
    pos = next;
  }
  return out;
}
