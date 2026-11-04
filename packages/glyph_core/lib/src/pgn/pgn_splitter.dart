import '../util/limits.dart';
import 'pgn_text.dart';

/// Result of [splitPgn].
class PgnSplit {
  const PgnSplit(this.chunks, {required this.truncated});

  /// One sanitised PGN text per game (headers + movetext).
  final List<String> chunks;

  /// True when more than the allowed number of games were present.
  final bool truncated;
}

final RegExp _headerStart = RegExp(r'[ \t]*\[[A-Za-z0-9][A-Za-z0-9_+#=:-]*[ \t]+"');
final RegExp _resultToken = RegExp(r'^(1-0|0-1|1/2-1/2|\*)$');
final RegExp _moveNumber = RegExp(r'^\d+\.');
final RegExp _sanLike = RegExp(
  r'^(O-O(-O)?|0-0(-0)?|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](=?[QRBNqrbn])?)[+#]?[!?]{0,2}$',
);

bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// Splits [text] (already passed through [normalizePgnText]) into games.
///
/// Unlike dartchess's own splitter this does not depend on blank lines between
/// games: a tag line after movetext, or a new move number after a result
/// token, starts a new game. It tracks `{}` comments (with nesting; inner
/// braces are rewritten to parentheses, because dartchess cannot parse nested
/// braces), `;` comments, `%` escape lines and `( )` variations, so none of
/// those can fake a game boundary. Comments longer than
/// [Limits.maxCommentBytes] are truncated. Text before the first game that is
/// not movetext (a "Check out my game" preamble) is dropped.
PgnSplit splitPgn(String text, {int maxGames = Limits.maxGamesPerFile}) {
  final chunks = <String>[];
  var buf = StringBuffer();
  var hasHeader = false;
  var hasMoves = false;
  var afterResult = false;
  var paren = 0;
  var needBlank = false; // a blank line separates the tags from the movetext
  var nestingBroken = false; // an unterminated nested comment was seen
  var truncated = false;

  // Adjacent comments are merged into one (dartchess is quadratic in the
  // number of comments on a single move) and capped at maxCommentBytes.
  StringBuffer? pending;
  var pendingBytes = 0;
  void startMovetext() {
    if (needBlank) buf.write('\n');
    needBlank = false;
  }

  void emitPending() {
    final p = pending;
    if (p == null) return;
    startMovetext();
    buf
      ..write('{')
      ..write(p)
      ..write('} ');
    pending = null;
    pendingBytes = 0;
  }

  void flush() {
    emitPending();
    if (hasHeader || hasMoves) chunks.add('${buf.toString().trimRight()}\n');
    buf = StringBuffer();
    hasHeader = false;
    hasMoves = false;
    afterResult = false;
    paren = 0;
    needBlank = false;
  }

  final n = text.length;
  var i = 0;
  scan:
  while (i < n) {
    if (chunks.length > maxGames) {
      truncated = true;
      break;
    }
    // --- at the start of a line ---
    var eol = text.indexOf('\n', i);
    if (eol < 0) eol = n;
    if (text.codeUnitAt(i) == 0x25 /* % */) {
      i = eol + 1;
      continue;
    }
    if (paren == 0 && _headerStart.matchAsPrefix(text, i) != null) {
      emitPending();
      if (hasMoves || afterResult) flush();
      hasHeader = true;
      needBlank = true;
      buf
        ..write(text.substring(i, eol).trim())
        ..write('\n');
      i = eol + 1;
      continue;
    }
    // --- movetext, until the end of the line (comments may run on) ---
    while (i < n) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        i++;
        continue scan;
      }
      if (_isWs(c)) {
        i++;
        continue;
      }
      if (c == 0x7B /* { */) {
        var end = -1;
        if (!nestingBroken) {
          var depth = 0;
          for (var j = i; j < n; j++) {
            final d = text.codeUnitAt(j);
            if (d == 0x7B) {
              depth++;
            } else if (d == 0x7D && --depth == 0) {
              end = j;
              break;
            }
          }
          if (end < 0) nestingBroken = true;
        }
        if (end < 0) {
          end = text.indexOf('}', i + 1);
          if (end < 0) end = n;
        }
        if (hasHeader || hasMoves) {
          final room = Limits.maxCommentBytes - pendingBytes;
          if (room > 0 && end > i + 1) {
            final body = truncateUtf8(
              text.substring(i + 1, end).replaceAll('{', '(').replaceAll('}', ')'),
              room,
            );
            if (body.isNotEmpty) {
              final p = pending ??= StringBuffer();
              if (pendingBytes > 0) {
                p.write(' ');
                pendingBytes++;
              }
              p.write(body);
              pendingBytes += utf8Length(body);
            }
          }
        }
        i = end + 1;
        continue;
      }
      if (c == 0x3B /* ; */) {
        final e = text.indexOf('\n', i);
        i = e < 0 ? n : e;
        continue;
      }
      if (c == 0x28 /* ( */) {
        emitPending();
        startMovetext();
        paren++;
        buf.write('( ');
        i++;
        continue;
      }
      if (c == 0x29 /* ) */) {
        emitPending();
        if (paren > 0) paren--;
        buf.write(') ');
        i++;
        continue;
      }
      // A token.
      var j = i;
      while (j < n) {
        final d = text.codeUnitAt(j);
        if (_isWs(d) || d == 0x7B || d == 0x3B || d == 0x28 || d == 0x29) break;
        j++;
      }
      final token = text.substring(i, j);
      i = j;
      emitPending();
      if (paren > 0) {
        buf
          ..write(token)
          ..write(' ');
        continue;
      }
      if (_resultToken.hasMatch(token)) {
        if (hasHeader || hasMoves) {
          afterResult = true;
          startMovetext();
          buf
            ..write(token)
            ..write(' ');
        }
        continue;
      }
      final startsMoveNumber = _moveNumber.hasMatch(token);
      if (afterResult) {
        if (!startsMoveNumber) continue; // trailing junk after a result
        flush();
      }
      final moveLike = startsMoveNumber ||
          _sanLike.hasMatch(token) ||
          token == '--' ||
          token.startsWith(r'$');
      if (moveLike && !token.startsWith(r'$')) hasMoves = true;
      if (hasHeader || hasMoves) {
        startMovetext();
        buf
          ..write(token)
          ..write(' ');
      }
    }
  }
  if (!truncated) flush();
  if (chunks.length > maxGames) {
    truncated = true;
    chunks.length = maxGames;
  }
  return PgnSplit(chunks, truncated: truncated);
}
