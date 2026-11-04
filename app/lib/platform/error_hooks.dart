import 'package:flutter/foundation.dart';

import 'app_log.dart';

/// Routes every uncaught error through [AppLog] (type only).
///
/// Flutter's default handlers print the exception *message* and a stack trace
/// to logcat, in release builds too. A message can carry a SQL statement, a
/// URL with a lichess / chess.com username, or part of a PGN, which
/// `docs/PRIVACY.md` section 5 promises never to log. So in release the
/// framework handler and the platform dispatcher handler (uncaught async
/// errors, the zone-less replacement of `runZonedGuarded`) log "what + type"
/// and nothing else; the error is then considered handled (the app does not
/// crash on an unawaited failure, as before).
///
/// In debug builds the framework's own reporting is kept, because a developer
/// needs the message and the stack.
///
/// Not covered: errors inside the engine's own isolate and native crashes;
/// those leave only Android's own report on the device and never contain
/// app data (the engine sees FENs and UCI lines, not names).
void installErrorHooks({bool debug = kDebugMode}) {
  final previous = FlutterError.onError;
  FlutterError.onError = (report) {
    if (debug) {
      (previous ?? FlutterError.presentError)(report);
      return;
    }
    AppLog.warning('Framework error', report.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.warning('Uncaught error', error);
    return true;
  };
}
