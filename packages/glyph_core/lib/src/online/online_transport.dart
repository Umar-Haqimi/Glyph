import 'dart:async';

import 'package:http/http.dart' as http;

import '../llm/idle_timeout.dart';
import '../llm/llm_client.dart' show HttpClientFactory;
import '../util/limits.dart';
import 'online_models.dart';

/// Thrown inside a fetch when the caller cancelled it.
class OnlineCancelled implements Exception {
  const OnlineCancelled();
}

/// The HTTP plumbing shared by [LichessClient] and [ChessComClient]: one GET
/// at a time with the SPEC 6 timeouts, no redirects, a `User-Agent`, an
/// abortable request, and the 429 policy (wait, tell the caller, retry).
///
/// The `User-Agent` is whatever the app passes (a generic `Glyph/version (+repo URL)` string: never an e-mail address or anything about the user).
class OnlineTransport {
  OnlineTransport({
    required HttpClientFactory httpClient,
    required this.userAgent,
    this.timeouts = const OnlineTimeouts(),
    this.rateLimitWait = Limits.rateLimitWait,
    this.maxRateLimitRetries = Limits.maxRateLimitRetries,
    Future<void> Function(Duration)? sleep,
  })  : _factory = httpClient,
        _sleep = sleep ?? Future<void>.delayed;

  final HttpClientFactory _factory;
  final String userAgent;
  final OnlineTimeouts timeouts;

  /// Minimum wait after a 429. SPEC / lichess: a full minute. Tests lower it
  /// together with a fake sleep; the app never changes it.
  final Duration rateLimitWait;
  final int maxRateLimitRetries;
  final Future<void> Function(Duration) _sleep;

  /// GETs [uri] and hands the response to [handle]. A 429 is never given to
  /// [handle]: it is waited out ([OnlineBackoff] events, cancellable) and
  /// retried up to [maxRateLimitRetries] times, then fails with
  /// [OnlineErrorKind.rateLimited]. Every other status is [handle]'s business
  /// (see [errorForStatus]).
  ///
  /// Throws [OnlineCancelled] when [token] is cancelled and
  /// [OnlineFetchException] for every failure.
  Future<T> get<T>(
    Uri uri, {
    required OnlineSource source,
    required OnlineCancelToken token,
    required void Function(OnlineEvent) onEvent,
    Map<String, String> headers = const {},
    required Future<T> Function(http.StreamedResponse response) handle,
  }) async {
    for (var attempt = 0;; attempt++) {
      if (token.isCancelled) throw const OnlineCancelled();
      final abort = Completer<void>();
      void trigger() {
        if (!abort.isCompleted) abort.complete();
      }

      final client = _factory();
      var timedOut = false;
      final timer = Timer(timeouts.total, () {
        timedOut = true;
        trigger();
      });
      unawaited(token.whenCancelled.then((_) => trigger()));
      Duration wait;
      try {
        final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll({'User-Agent': userAgent, ...headers});
        final response = await client.send(request).timeout(timeouts.firstByte);
        if (response.statusCode != 429) {
          final value = await handle(response);
          if (token.isCancelled) throw const OnlineCancelled();
          return value;
        }
        wait = _waitFor(response);
      } on OnlineCancelled {
        rethrow;
      } on OnlineFetchException {
        if (token.isCancelled) throw const OnlineCancelled();
        rethrow;
      } on Object catch (e) {
        if (token.isCancelled) throw const OnlineCancelled();
        if (timedOut) throw const OnlineFetchException(OnlineFetchError(OnlineErrorKind.timeout));
        throw OnlineFetchException(OnlineFetchError(_kindOf(e)));
      } finally {
        timer.cancel();
        client.close();
      }
      if (attempt >= maxRateLimitRetries) {
        throw const OnlineFetchException(OnlineFetchError(OnlineErrorKind.rateLimited, status: 429));
      }
      await _backoff(source, wait, token, onEvent);
    }
  }

  /// Reads [response] chunk by chunk, with the idle limit and the
  /// [Limits.maxOnlineResponseBytes] cap. [onChunk] returns true to stop
  /// early. Returns when the body ended, [onChunk] asked to stop, or the
  /// fetch was cancelled (the caller checks the token).
  Future<void> readChunks(
    http.StreamedResponse response,
    OnlineCancelToken token,
    bool Function(List<int> chunk) onChunk, {
    int maxBytes = Limits.maxOnlineResponseBytes,
  }) {
    // Not `await for` + `break`: that awaits the cancellation of the body.
    final finished = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    var total = 0;

    void stop([Object? error]) {
      unawaited(sub.cancel());
      if (finished.isCompleted) return;
      if (error == null) {
        finished.complete();
      } else {
        finished.completeError(error);
      }
    }

    sub = idleTimeout(response.stream, timeouts.firstByte).listen(
      (chunk) {
        if (finished.isCompleted) return;
        total += chunk.length;
        if (total > maxBytes) {
          stop(const OnlineFetchException(OnlineFetchError(OnlineErrorKind.tooLarge)));
          return;
        }
        try {
          if (onChunk(chunk)) stop();
        } on Object catch (e) {
          stop(e);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!finished.isCompleted) finished.completeError(e, st);
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    unawaited(token.whenCancelled.then((_) => stop()));
    return finished.future;
  }

  /// Collects the whole body (capped).
  Future<List<int>> readAll(http.StreamedResponse response, OnlineCancelToken token) async {
    final out = <int>[];
    await readChunks(response, token, (chunk) {
      out.addAll(chunk);
      return false;
    });
    return out;
  }

  /// The error for a non-2xx [status] (404 is [notFound], default
  /// [OnlineErrorKind.userNotFound]).
  static OnlineFetchError errorForStatus(int status, {OnlineErrorKind notFound = OnlineErrorKind.userNotFound}) {
    if (status == 404) return OnlineFetchError(notFound, status: status);
    if (status == 410) return OnlineFetchError(OnlineErrorKind.unavailable, status: status);
    return OnlineFetchError(OnlineErrorKind.server, status: status);
  }

  /// At least [rateLimitWait], more if `Retry-After` (seconds) asks for it,
  /// never more than [Limits.maxRateLimitWait].
  Duration _waitFor(http.StreamedResponse response) {
    var wait = rateLimitWait;
    final seconds = int.tryParse((response.headers['retry-after'] ?? '').trim());
    if (seconds != null && seconds > 0 && Duration(seconds: seconds) > wait) wait = Duration(seconds: seconds);
    return wait > Limits.maxRateLimitWait ? Limits.maxRateLimitWait : wait;
  }

  Future<void> _backoff(
    OnlineSource source,
    Duration total,
    OnlineCancelToken token,
    void Function(OnlineEvent) onEvent,
  ) async {
    var remaining = total;
    const tick = Duration(seconds: 1);
    while (remaining > Duration.zero) {
      if (token.isCancelled) throw const OnlineCancelled();
      onEvent(OnlineBackoff(source, remaining, total));
      if (token.isCancelled) throw const OnlineCancelled();
      final step = remaining < tick ? remaining : tick;
      await Future.any([_sleep(step), token.whenCancelled]);
      remaining -= step;
    }
    if (token.isCancelled) throw const OnlineCancelled();
  }

  static OnlineErrorKind _kindOf(Object error) {
    if (error is TimeoutException) return OnlineErrorKind.timeout;
    final type = error.runtimeType.toString();
    final text = error.toString().toLowerCase();
    if (type.contains('Handshake') || type.contains('Tls') || text.contains('certificate') || text.contains('handshake')) {
      return OnlineErrorKind.tls;
    }
    if (text.contains('timed out') || text.contains('timeout')) return OnlineErrorKind.timeout;
    if (error is http.ClientException ||
        type.contains('Socket') ||
        type.contains('Http') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('connection terminated') ||
        text.contains('no route to host')) {
      return OnlineErrorKind.offline;
    }
    return OnlineErrorKind.badResponse;
  }
}
