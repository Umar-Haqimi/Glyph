import 'dart:developer' as developer;

/// The app's single logging wrapper (SPEC 6: nothing below warning, and never
/// user data). Only a fixed [what] and the error's *type* are logged: error
/// messages can embed PGN text, file names or keys, so they are dropped.
abstract final class AppLog {
  /// Replaced in tests to capture lines.
  static void Function(String line) sink = (line) => developer.log(line, name: 'glyph', level: 900);

  static void warning(String what, Object error) => sink('$what (${error.runtimeType})');
}
