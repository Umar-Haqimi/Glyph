import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/platform/app_log.dart';
import 'package:glyph/platform/error_hooks.dart';

/// docs/PRIVACY.md section 5: an uncaught error never puts its message (SQL, a
/// URL with a username, PGN text) into the log, in a release build.
void main() {
  const secret = 'SELECT pgn FROM games WHERE white = \'hikaru\' https://lichess.org/api/games/user/hikaru';

  late FlutterExceptionHandler? oldFlutter;
  late ErrorCallback? oldDispatcher;
  late void Function(String) oldSink;
  late List<String> lines;

  setUp(() {
    oldFlutter = FlutterError.onError;
    oldDispatcher = PlatformDispatcher.instance.onError;
    oldSink = AppLog.sink;
    lines = [];
    AppLog.sink = lines.add;
  });
  tearDown(() {
    FlutterError.onError = oldFlutter;
    PlatformDispatcher.instance.onError = oldDispatcher;
    AppLog.sink = oldSink;
  });

  test('release: framework errors and uncaught async errors are logged by type only', () {
    installErrorHooks(debug: false);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError(secret), stack: StackTrace.current, library: 'glyph', context: ErrorDescription(secret)));
    final handled = PlatformDispatcher.instance.onError!(ArgumentError(secret), StackTrace.current);
    expect(handled, isTrue, reason: 'handled: the app does not crash on an unawaited failure');
    expect(lines, ['Framework error (StateError)', 'Uncaught error (ArgumentError)']);
    for (final line in lines) {
      expect(line, isNot(contains('hikaru')));
      expect(line, isNot(contains('SELECT')));
      expect(line, isNot(contains('lichess')));
    }
  });

  test('debug keeps the framework\'s own report for developers (and still logs async errors by type)', () {
    var previousCalls = 0;
    FlutterError.onError = (_) => previousCalls++;
    installErrorHooks(debug: true);
    FlutterError.onError!(FlutterErrorDetails(exception: StateError(secret)));
    expect(previousCalls, 1);
    expect(lines, isEmpty);
    PlatformDispatcher.instance.onError!(StateError(secret), StackTrace.current);
    expect(lines.single, 'Uncaught error (StateError)');
  });

  test('main() installs the hooks before the app starts', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.indexOf('installErrorHooks()'), isNonNegative);
    expect(main.indexOf('installErrorHooks()'), lessThan(main.indexOf('runApp(')));
  });
}
