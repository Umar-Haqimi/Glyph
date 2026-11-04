/// The only thing the analysis pipeline knows about an engine (SPEC 5.2).
///
/// Implementations: `MultistockfishDriver` (device, in the app),
/// `ProcessEngineDriver` (host, a desktop binary), `FakeEngineDriver`
/// (recorded transcripts).
abstract interface class EngineDriver {
  /// Engine output, one event per line. Broadcast. The stream completes when
  /// the engine exits (a crash if nobody asked it to quit) and may emit an
  /// error.
  Stream<String> get lines;

  /// Writes one UCI command (a trailing newline is added by the driver).
  void send(String command);

  /// Asks the engine to quit and releases everything. Idempotent.
  Future<void> dispose();
}

/// Creates a started engine. The pipeline calls it lazily and again after the
/// engine was discarded (crash, stop timeout, pause).
typedef EngineDriverFactory = Future<EngineDriver> Function();

/// The engine process exited, or its output stream ended, while the pipeline
/// was waiting for it.
class EngineClosedException implements Exception {
  const EngineClosedException([this.message = 'The engine stopped unexpectedly.']);

  final String message;

  @override
  String toString() => 'EngineClosedException: $message';
}

/// The engine did not answer within the allowed time.
class EngineTimeoutException implements Exception {
  const EngineTimeoutException(this.message);

  final String message;

  @override
  String toString() => 'EngineTimeoutException: $message';
}

/// The engine reported that it rejected our input (`CRITICAL ERROR ...`).
class EngineProtocolException implements Exception {
  const EngineProtocolException(this.message);

  final String message;

  @override
  String toString() => 'EngineProtocolException: $message';
}
