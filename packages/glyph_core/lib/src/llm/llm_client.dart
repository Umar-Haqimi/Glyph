import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/limits.dart';
import 'base_url_policy.dart';
import 'chat_stream.dart';
import 'idle_timeout.dart';
import 'llm_error.dart';
import 'llm_models.dart';
import 'sse_decoder.dart';

/// Creates the HTTP client of one request; the client closes it afterwards.
/// The app passes a factory that sets the 15 s connection timeout on the
/// `dart:io` client; tests pass a `MockClient` or a plain client aimed at a
/// local server.
typedef HttpClientFactory = http.Client Function();

/// Request timeouts (SPEC 6: connect 15 s, first byte 60 s, total 180 s).
///
/// The connect timeout belongs to the HTTP client the factory builds (the
/// `http` interface has no such knob); [firstByte] bounds the wait for the
/// response headers **and** every later gap between two chunks (so a stream
/// of keep-alive comments does not hide a stalled model for ever, while a
/// slow reasoning model gets a full minute); [total] bounds the whole call.
class LlmTimeouts {
  const LlmTimeouts({
    this.connect = Limits.connectTimeout,
    this.firstByte = Limits.firstByteTimeout,
    this.total = Limits.totalTimeout,
  });

  static const standard = LlmTimeouts();

  final Duration connect;
  final Duration firstByte;
  final Duration total;
}

/// OpenAI-compatible chat completions over HTTP (SPEC 2.1 "LLM API"):
/// `POST {baseUrl}/chat/completions`, `Authorization: Bearer <key>`, body
/// `{model, messages, stream: true}`, answer as server-sent events.
///
/// * The base URL goes through [BaseUrlPolicy] before any socket is opened.
/// * The API key is read from [readApiKey] when the request is built and is
///   only ever put into the `Authorization` header: never in the body, a
///   log line, an error, or the "View prompt" text. Error details coming back
///   from the provider have any occurrence of it removed.
/// * Redirects are **not** followed (a redirect must not carry the key to
///   another host or downgrade to http); a 3xx is reported as
///   [LlmErrorKind.endpointNotFound].
/// * Cancelling the returned stream's subscription aborts the request and
///   closes the client.
class LlmClient {
  LlmClient({required HttpClientFactory httpClient, this.timeouts = LlmTimeouts.standard}) : _factory = httpClient;

  final HttpClientFactory _factory;
  final LlmTimeouts timeouts;

  /// Streams the answer to [request] ([LlmRequest.stream] is forced on).
  ///
  /// Emits [LlmTextDelta]s and finally one [LlmFinished]; a failure is added
  /// to the stream as an [LlmException] (and ends it). Listening starts the
  /// request; cancelling the subscription cancels it.
  Stream<LlmEvent> stream(LlmRequest request, {required Future<String?> Function() readApiKey}) {
    final controller = StreamController<LlmEvent>();
    final abort = Completer<void>();
    http.Client? client;
    Timer? totalTimer;
    var cancelled = false;
    var timedOut = false;
    void Function()? cancelBody;

    void shutDown() {
      totalTimer?.cancel();
      cancelBody?.call();
      if (!abort.isCompleted) abort.complete();
      client?.close();
    }

    Future<void> run() async {
      String? key;
      try {
        final config = request.config;
        final policy = BaseUrlPolicy.check(config.baseUrl);
        if (!policy.ok) throw LlmException(LlmError(_policyKind(policy.problem!)));
        key = await readApiKey();
        if (cancelled) return;
        client = _factory();
        totalTimer = Timer(timeouts.total, () {
          timedOut = true;
          shutDown();
        });
        final response = await _post(client!, BaseUrlPolicy.chatCompletions(policy.uri!), LlmRequest(config: config, messages: request.messages), key, abort.future);
        if (cancelled) return;
        await _readResponse(response, controller, () => cancelled, (cancel) => cancelBody = cancel);
      } on Object catch (e) {
        if (cancelled) return;
        final error = timedOut ? const LlmError(LlmErrorKind.timeout) : _redact(ErrorMapper.fromException(e), key);
        if (!controller.isClosed) controller.addError(LlmException(error));
      } finally {
        shutDown();
        if (!controller.isClosed) unawaited(controller.close());
      }
    }

    controller.onListen = () => unawaited(run());
    controller.onCancel = () {
      cancelled = true;
      shutDown();
    };
    return controller.stream;
  }

  /// A tiny non-streamed request for "Test connection" (SPEC F13): null when
  /// the endpoint, the key and the model all work, else what went wrong.
  Future<LlmError?> testConnection(LlmConfig config, {required Future<String?> Function() readApiKey}) async {
    final policy = BaseUrlPolicy.check(config.baseUrl);
    if (!policy.ok) return LlmError(_policyKind(policy.problem!));
    if (config.model.trim().isEmpty) return const LlmError(LlmErrorKind.noModel);
    final abort = Completer<void>();
    final client = _factory();
    String? key;
    final timer = Timer(timeouts.total, () {
      if (!abort.isCompleted) abort.complete();
      client.close();
    });
    try {
      key = await readApiKey();
      final probe = LlmRequest(
        config: LlmConfig(
          baseUrl: config.baseUrl,
          model: config.model,
          tokenLimitMode: config.tokenLimitMode,
          tokenLimit: config.tokenLimit < 16 ? config.tokenLimit : 16,
        ),
        messages: const [ChatMessage(ChatRole.user, 'Reply with the single word OK.')],
        stream: false,
      );
      final response = await _post(client, BaseUrlPolicy.chatCompletions(policy.uri!), probe, key, abort.future);
      final body = await ErrorMapper.readBody(idleTimeout(response.stream, timeouts.firstByte));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _redact(ErrorMapper.fromHttp(response.statusCode, body), key);
      }
      parseCompleteResponse(body);
      return null;
    } on Object catch (e) {
      return _redact(ErrorMapper.fromException(e), key);
    } finally {
      timer.cancel();
      client.close();
    }
  }

  Future<http.StreamedResponse> _post(
    http.Client client,
    Uri uri,
    LlmRequest request,
    String? key,
    Future<void> abortTrigger,
  ) {
    final req = _request(uri, request, key, abortTrigger);
    return client.send(req).timeout(timeouts.firstByte);
  }

  http.BaseRequest _request(Uri uri, LlmRequest request, String? key, Future<void> abortTrigger) {
    final req = http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = request.stream ? 'text/event-stream, application/json' : 'application/json'
      ..body = request.body();
    if (key != null && key.isNotEmpty) req.headers['Authorization'] = 'Bearer $key';
    return req;
  }

  Future<void> _readResponse(
    http.StreamedResponse response,
    StreamController<LlmEvent> out,
    bool Function() isCancelled,
    void Function(void Function() cancel) track,
  ) async {
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final body = await ErrorMapper.readBody(idleTimeout(response.stream, timeouts.firstByte));
      throw LlmException(ErrorMapper.fromHttp(status, body));
    }
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('application/json')) {
      // A server that ignored `stream: true`.
      final body = await ErrorMapper.readBody(idleTimeout(response.stream, timeouts.firstByte));
      final complete = parseCompleteResponse(body);
      if (complete.text.isEmpty) throw const LlmException(LlmError(LlmErrorKind.emptyResponse));
      final capped = _cap(complete.text, 0);
      out.add(LlmTextDelta(capped.text));
      out.add(LlmFinished(finishReason: complete.finishReason, truncated: capped.truncated));
      return;
    }

    final decoder = SseDecoder();
    var textBytes = 0;
    var sawDone = false;
    var sawFinish = false;
    String? finishReason;
    var truncated = false;

    // Returns true when reading can stop.
    bool handle(List<SseEvent> events) {
      for (final event in events) {
        for (final item in parseChatEvent(event)) {
          switch (item) {
            case ChatDelta(:final text):
              final capped = _cap(text, textBytes);
              if (capped.text.isNotEmpty) {
                textBytes += utf8.encode(capped.text).length;
                out.add(LlmTextDelta(capped.text));
              }
              if (capped.truncated) {
                truncated = true;
                return true;
              }
            case ChatFinish(:final reason):
              sawFinish = true;
              finishReason = reason;
            case ChatDone():
              sawDone = true;
              return true;
            case ChatFailure(:final error):
              throw LlmException(error);
          }
        }
      }
      return false;
    }

    // Not `await for` + `break`: that awaits the cancellation of the body
    // stream, which under a fake-async test zone may never complete; the
    // subscription is cancelled without waiting instead.
    final finished = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    track(() {
      // Called when the call is cancelled or timed out: stop reading and let
      // the wait below end (a cancelled subscription sends no done event).
      unawaited(sub.cancel());
      if (!finished.isCompleted) finished.complete();
    });
    sub = idleTimeout(response.stream, timeouts.firstByte).listen(
      (chunk) {
        if (isCancelled() || finished.isCompleted) return;
        try {
          if (handle(decoder.add(chunk))) {
            unawaited(sub.cancel());
            finished.complete();
          }
        } on SseFormatException {
          unawaited(sub.cancel());
          finished.completeError(const LlmException(LlmError(LlmErrorKind.badStream)));
        } on Object catch (e, st) {
          unawaited(sub.cancel());
          finished.completeError(e, st);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!finished.isCompleted) finished.completeError(e, st);
      },
      onDone: () {
        if (finished.isCompleted) return;
        try {
          handle(decoder.close());
          finished.complete();
        } on SseFormatException {
          finished.completeError(const LlmException(LlmError(LlmErrorKind.badStream)));
        } on Object catch (e, st) {
          finished.completeError(e, st);
        }
      },
      cancelOnError: true,
    );
    await finished.future;
    if (isCancelled()) return;
    if (!truncated && !sawDone && !sawFinish) throw const LlmException(LlmError(LlmErrorKind.badStream));
    if (textBytes == 0) throw const LlmException(LlmError(LlmErrorKind.emptyResponse));
    out.add(LlmFinished(finishReason: finishReason, truncated: truncated));
  }

  /// [text] cut so that the whole answer stays within
  /// [Limits.maxLlmStreamBytes] (never inside a UTF-8 sequence).
  static ({String text, bool truncated}) _cap(String text, int usedBytes) {
    final bytes = utf8.encode(text);
    final room = Limits.maxLlmStreamBytes - usedBytes;
    if (bytes.length <= room) return (text: text, truncated: false);
    var end = room < 0 ? 0 : room;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return (text: utf8.decode(bytes.sublist(0, end), allowMalformed: true), truncated: true);
  }

  static LlmErrorKind _policyKind(BaseUrlProblem problem) => problem == BaseUrlProblem.cleartextNotAllowed
      ? LlmErrorKind.cleartextBlocked
      : LlmErrorKind.invalidUrl;

  /// Removes the API key (and its `Bearer` form) from the provider's text.
  static LlmError _redact(LlmError error, String? key) {
    final detail = error.detail;
    if (detail == null || key == null || key.length < 6) return error;
    return LlmError(error.kind, status: error.status, param: error.param, detail: detail.replaceAll(key, '***'));
  }
}
