import '../game/game.dart';

/// A file name made only of `A-Z a-z 0-9 . _ -`: everything else becomes `_`,
/// runs of `_` / `.` collapse, leading and trailing separators go, and the
/// result is at most [maxLength] characters. Never empty ([fallback] then).
/// The name is used for the shared PGN file and the share subject, so it must
/// not be able to carry a path (`/`, `\`, `..`), a control character or an
/// extension of its own.
String sanitizeFileName(String raw, {int maxLength = 80, String fallback = 'game'}) {
  var s = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  s = s.replaceAll(RegExp(r'_{2,}'), '_').replaceAll(RegExp(r'\.{2,}'), '.');
  s = s.replaceAll(RegExp(r'[_.]*\.[_.]*'), '.').replaceAll(RegExp(r'^[_.-]+|[_.-]+$'), '');
  if (s.length > maxLength) s = s.substring(0, maxLength).replaceAll(RegExp(r'[_.-]+$'), '');
  return s.isEmpty ? fallback : s;
}

/// `white_vs_black_2026-10-23.pgn`, sanitised (SPEC F18: share sheet, no
/// storage permission, so the name only has to be safe and readable).
String exportFileName(Game game) {
  final white = game.white == null ? '' : sanitizeFileName(game.white!, maxLength: 24, fallback: '');
  final black = game.black == null ? '' : sanitizeFileName(game.black!, maxLength: 24, fallback: '');
  final date = game.date?.replaceAll('.', '-').replaceAll('?', '');
  final players = white.isEmpty && black.isEmpty ? 'game' : '${white.isEmpty ? 'unknown' : white}_vs_${black.isEmpty ? 'unknown' : black}';
  final stem = sanitizeFileName(date == null || date.isEmpty ? players : '${players}_$date', maxLength: 70);
  return '$stem.pgn';
}
