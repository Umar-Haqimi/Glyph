/// Username formats, checked before anything is sent anywhere (the name goes
/// into a URL path, and into a settings row).
abstract final class Usernames {
  /// lila `User.historicalUsernameRegex`: 2 to 30 letters, digits, `_` and `-`,
  /// starting and ending with a letter or digit.
  static final _lichess = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,28}[A-Za-z0-9]$');

  /// chess.com: 3 to 25 letters, digits, `_` and `-`.
  static final _chessCom = RegExp(r'^[A-Za-z0-9_-]{3,25}$');

  static bool isValidLichess(String name) => _lichess.hasMatch(name);

  static bool isValidChessCom(String name) => _chessCom.hasMatch(name);
}
