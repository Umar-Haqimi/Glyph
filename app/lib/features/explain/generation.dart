import 'dart:async';

import 'package:glyph_core/glyph_core.dart';

import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../platform/app_log.dart';

/// The ExplainRequest state machine of SPEC 4 (idle -> connecting ->
/// streaming -> done, plus cancelled and failed(kind)), shared by the Explain
/// sheet and the game summary, with the two extra states the UI needs: the
/// not-configured gate in front of it and `idle` before a summary was asked
/// for.
enum GenerationPhase { idle, notConfigured, connecting, streaming, done, failed, cancelled }

class GenerationState {
  const GenerationState({
    this.phase = GenerationPhase.idle,
    this.text = '',
    this.error,
    this.request,
    this.fromCache = false,
    this.cutOff = false,
    this.missing,
  });

  const GenerationState.idle() : this();
  const GenerationState.connecting({LlmRequest? request}) : this(phase: GenerationPhase.connecting, request: request);
  const GenerationState.notConfigured(LlmErrorKind problem) : this(phase: GenerationPhase.notConfigured, missing: problem);

  final GenerationPhase phase;

  /// The answer so far (complete when [phase] is done).
  final String text;
  final LlmError? error;

  /// The exact request, for "View prompt". Null until the prompt was built.
  final LlmRequest? request;

  /// The text came from the cache, not from the model.
  final bool fromCache;

  /// The text ends early: the 32 KB stream cap or the model's token limit.
  final bool cutOff;

  /// What the not-configured gate found missing.
  final LlmErrorKind? missing;

  bool get busy => phase == GenerationPhase.connecting || phase == GenerationPhase.streaming;

  GenerationState copyWith({
    GenerationPhase? phase,
    String? text,
    LlmError? error,
    LlmRequest? request,
    bool? fromCache,
    bool? cutOff,
  }) =>
      GenerationState(
        phase: phase ?? this.phase,
        text: text ?? this.text,
        error: error ?? this.error,
        request: request ?? this.request,
        fromCache: fromCache ?? this.fromCache,
        cutOff: cutOff ?? this.cutOff,
        missing: missing,
      );
}

/// Runs one request at a time: cache lookup, streaming, cache write, and
/// cancellation. One request in flight per owner (SPEC 5.3); a new [run] or
/// [cancel] drops the previous subscription, which aborts its HTTP request.
class GenerationRunner {
  GenerationRunner({
    required this.client,
    required this.readApiKey,
    required this.cache,
    required this.nowMs,
    required this.onChange,
  });

  final LlmClient client;
  final Future<String?> Function() readApiKey;
  final LlmCacheRepository cache;
  final int Function() nowMs;
  final void Function(GenerationState state) onChange;

  GenerationState _state = const GenerationState.idle();
  StreamSubscription<LlmEvent>? _sub;
  Completer<void>? _pending;
  int _generation = 0;
  bool _disposed = false;

  GenerationState get state => _state;

  void _emit(GenerationState s) {
    _state = s;
    if (!_disposed) onChange(s);
  }

  /// Asks the model (or the cache, when [useCache]) and completes when the
  /// request ended in any way.
  Future<void> run({
    required LlmRequest request,
    required String cacheKey,
    required PromptKind kind,
    int? gameId,
    bool useCache = true,
  }) async {
    _drop();
    final id = ++_generation;
    _emit(GenerationState.connecting(request: request));

    if (useCache) {
      CachedLlmText? hit;
      try {
        hit = await cache.get(cacheKey);
      } on Object catch (e) {
        AppLog.warning('Reading the explanation cache failed', e);
      }
      if (id != _generation || _disposed) return;
      if (hit != null) {
        _emit(GenerationState(phase: GenerationPhase.done, text: hit.content, request: request, fromCache: true));
        return;
      }
    }

    final done = _pending = Completer<void>();
    var text = '';
    LlmFinished? finished;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    _sub = client.stream(request, readApiKey: readApiKey).listen(
      (event) {
        if (id != _generation) return;
        switch (event) {
          case LlmTextDelta(text: final piece):
            text += piece;
            _emit(GenerationState(phase: GenerationPhase.streaming, text: text, request: request));
          case LlmFinished():
            finished = event;
        }
      },
      onError: (Object e) {
        if (id != _generation) return;
        final error = e is LlmException ? e.error : ErrorMapper.fromException(e);
        _emit(GenerationState(phase: GenerationPhase.failed, text: text, error: error, request: request));
        finish();
      },
      onDone: () async {
        if (id != _generation) return finish();
        final f = finished;
        if (f == null) {
          _emit(GenerationState(
            phase: GenerationPhase.failed,
            text: text,
            error: const LlmError(LlmErrorKind.badStream),
            request: request,
          ));
          return finish();
        }
        if (!f.cutOff) {
          // A complete answer is worth keeping; a cut-off one is not.
          try {
            await cache.put(CachedLlmText(
              key: cacheKey,
              kind: kind,
              content: text,
              model: request.config.model,
              createdAt: nowMs(),
              gameId: gameId,
            ));
          } on Object catch (e) {
            AppLog.warning('Saving the explanation failed', e);
          }
        }
        if (id == _generation) {
          _emit(GenerationState(phase: GenerationPhase.done, text: text, request: request, cutOff: f.cutOff));
        }
        finish();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  /// Stops the request in flight (Stop button, or closing the sheet). Keeps
  /// the text received so far.
  void cancel() {
    if (_state.busy) {
      _generation++;
      _emit(GenerationState(
        phase: GenerationPhase.cancelled,
        text: _state.text,
        request: _state.request,
      ));
    }
    _drop();
  }

  void _drop() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Ends the owner's life: aborts the request without any further state.
  void dispose() {
    _disposed = true;
    _generation++;
    _drop();
  }

  /// Resets to a state without a request (e.g. the gate said not configured).
  void reset(GenerationState s) {
    _drop();
    _generation++;
    _emit(s);
  }
}
