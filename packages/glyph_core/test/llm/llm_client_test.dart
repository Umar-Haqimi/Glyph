import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:test/test.dart';

/// A local fake OpenAI-compatible server (no real network). 127.0.0.1 is a
/// loopback address, so `BaseUrlPolicy` lets plain http through.
class FakeServer {
  FakeServer._(this.server);

  final HttpServer server;
  final requests = <RecordedRequest>[];
  Future<void> Function(HttpRequest request, RecordedRequest recorded)? handler;
  final closedByClient = <Completer<void>>[];

  static Future<FakeServer> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeServer._(s);
    s.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final rec = RecordedRequest(req.method, req.uri.path, {
        for (final name in ['authorization', 'content-type', 'accept']) name: req.headers.value(name),
      }, body);
      fake.requests.add(rec);
      try {
        await fake.handler!(req, rec);
      } on Object {
        // client went away
      }
    });
    return fake;
  }

  String get baseUrl => 'http://127.0.0.1:${server.port}/v1';

  Future<void> close() => server.close(force: true);
}

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String?> headers;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// Starts an event-stream response that is sent as it is written (dart:io
/// buffers a response until it is closed unless `bufferOutput` is off).
void startStream(HttpResponse response) {
  response.bufferOutput = false;
  response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
}

String sse(String delta, {String? finish}) =>
    'data: ${jsonEncode({
      'id': 'x',
      'object': 'chat.completion.chunk',
      'choices': [
        {'index': 0, 'delta': delta.isEmpty ? <String, Object?>{} : {'content': delta}, 'finish_reason': finish},
      ],
    })}\n\n';

const secret = 'sk-test-SECRET-1234567890';

LlmRequest requestFor(String baseUrl, {TokenLimitMode mode = TokenLimitMode.none, int limit = 256, String model = 'gpt-test'}) =>
    LlmRequest(
      config: LlmConfig(baseUrl: baseUrl, model: model, tokenLimitMode: mode, tokenLimit: limit),
      messages: const [ChatMessage(ChatRole.system, 'sys'), ChatMessage(ChatRole.user, 'hello')],
    );

Future<({List<LlmEvent> events, LlmException? error})> collect(Stream<LlmEvent> stream) async {
  final events = <LlmEvent>[];
  LlmException? error;
  await stream.handleError((Object e) => error = e as LlmException).forEach(events.add);
  return (events: events, error: error);
}

String textOf(List<LlmEvent> events) => events.whereType<LlmTextDelta>().map((e) => e.text).join();

void main() {
  late FakeServer fake;
  setUp(() async => fake = await FakeServer.start());
  tearDown(() => fake.close());

  LlmClient client({LlmTimeouts timeouts = LlmTimeouts.standard}) =>
      LlmClient(httpClient: () => IOClient(HttpClient()..connectionTimeout = timeouts.connect), timeouts: timeouts);

  Future<String?> key() async => secret;

  group('request', () {
    test('POST {base}/chat/completions with bearer key, JSON body, stream:true, no temperature, no token limit', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('Hi'));
        req.response.write(sse('', finish: 'stop'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      final result = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(result.error, isNull);
      expect(textOf(result.events), 'Hi');
      final fin = result.events.last as LlmFinished;
      expect(fin.finishReason, 'stop');
      expect(fin.cutOff, isFalse);

      final r = fake.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/v1/chat/completions');
      expect(r.headers['authorization'], 'Bearer $secret');
      expect(r.headers['content-type'], startsWith('application/json'));
      expect(r.headers['accept'], contains('text/event-stream'));
      expect(r.json.keys.toSet(), {'model', 'messages', 'stream'});
      expect(r.json['stream'], true);
      expect(r.json['model'], 'gpt-test');
      expect(r.json['messages'], [
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(r.body, isNot(contains(secret)), reason: 'the key goes in the header only');
    });

    test('the token limit parameter is sent only when chosen, under the chosen name', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('x', finish: 'stop'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      await collect(client().stream(requestFor(fake.baseUrl, mode: TokenLimitMode.maxTokens, limit: 300), readApiKey: key));
      await collect(client().stream(requestFor(fake.baseUrl, mode: TokenLimitMode.maxCompletionTokens, limit: 400), readApiKey: key));
      expect(fake.requests[0].json['max_tokens'], 300);
      expect(fake.requests[0].json.containsKey('max_completion_tokens'), isFalse);
      expect(fake.requests[1].json['max_completion_tokens'], 400);
      expect(fake.requests[1].json.containsKey('max_tokens'), isFalse);
      expect(fake.requests[1].json.containsKey('temperature'), isFalse);
    });

    test('no key (Ollama): no Authorization header at all', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('ok', finish: 'stop'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      for (final k in <String?>[null, '']) {
        await collect(client().stream(requestFor(fake.baseUrl), readApiKey: () async => k));
      }
      for (final r in fake.requests) {
        expect(r.headers['authorization'], isNull);
      }
    });

    test('LlmRequest.toJson is exactly the body sent', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('ok', finish: 'stop'));
        await req.response.close();
      };
      final request = requestFor(fake.baseUrl, mode: TokenLimitMode.maxTokens, limit: 99);
      await collect(client().stream(request, readApiKey: key));
      expect(jsonDecode(fake.requests.single.body), request.toJson());
      expect(request.prettyBody(), isNot(contains(secret)));
    });
  });

  group('policy gate', () {
    test('plain http to a public host is refused before any connection', () async {
      final result = await collect(client().stream(requestFor('http://example.com/v1'), readApiKey: key));
      expect(result.error!.error.kind, LlmErrorKind.cleartextBlocked);
      expect(result.events, isEmpty);
    });

    test('other invalid URLs are refused, the key is not even read', () async {
      var keyReads = 0;
      final result = await collect(client().stream(requestFor('ftp://example.com/v1'), readApiKey: () async {
        keyReads++;
        return secret;
      }));
      expect(result.error!.error.kind, LlmErrorKind.invalidUrl);
      expect(keyReads, 0);
      expect(fake.requests, isEmpty);
    });
  });

  group('HTTP failures', () {
    Future<void> serve(int status, String body, {String type = 'application/json'}) async {
      fake.handler = (req, _) async {
        req.response.statusCode = status;
        req.response.headers.set('content-type', type);
        req.response.write(body);
        await req.response.close();
      };
    }

    test('401 -> unauthorized, 404 -> modelNotFound, 429 quota, 400 unsupported param with param name', () async {
      await serve(401, jsonEncode({'error': {'message': 'bad key', 'code': 'invalid_api_key'}}));
      expect((await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error.kind, LlmErrorKind.unauthorized);

      await serve(404, jsonEncode({'error': {'message': 'The model `x` does not exist', 'code': 'model_not_found'}}));
      expect((await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error.kind, LlmErrorKind.modelNotFound);

      await serve(429, jsonEncode({'error': {'code': 'insufficient_quota', 'message': 'no credits'}}));
      expect((await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error.kind, LlmErrorKind.quotaExceeded);

      await serve(400, jsonEncode({'error': {'code': 'unsupported_parameter', 'param': 'max_tokens', 'message': 'm'}}));
      final e = (await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error;
      expect(e.kind, LlmErrorKind.unsupportedParam);
      expect(e.param, 'max_tokens');
      expect(e.status, 400);

      await serve(503, '<html>down</html>', type: 'text/html');
      final s = (await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error;
      expect(s.kind, LlmErrorKind.server);
      expect(s.status, 503);
    });

    test('a provider message that echoes the key is redacted', () async {
      await serve(401, jsonEncode({'error': {'message': 'Incorrect API key provided: $secret.', 'code': 'invalid_api_key'}}));
      final e = (await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error;
      expect(e.detail, isNotNull);
      expect(e.detail, isNot(contains(secret)));
      expect(e.detail, contains('***'));
      expect(e.toString(), isNot(contains(secret)));
    });

    test('redirects are not followed (the key must not travel on)', () async {
      fake.handler = (req, _) async {
        req.response.statusCode = 307;
        req.response.headers.set('location', 'http://127.0.0.1:1/elsewhere');
        await req.response.close();
      };
      final e = (await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error;
      expect(e.kind, LlmErrorKind.endpointNotFound);
      expect(fake.requests, hasLength(1));
    });

    test('connection refused -> offline', () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close(force: true);
      final e = (await collect(client().stream(requestFor('http://127.0.0.1:$port/v1'), readApiKey: key))).error!.error;
      expect(e.kind, LlmErrorKind.offline);
    });
  });

  group('stream handling', () {
    test('an error event mid-stream: text so far, then the failure', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('part '));
        req.response.write(sse('one'));
        req.response.write('data: ${jsonEncode({'error': {'message': 'boom', 'type': 'server_error'}})}\n\n');
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(textOf(r.events), 'part one');
      expect(r.error!.error.kind, LlmErrorKind.server);
    });

    test('closing without [DONE] or finish_reason is a bad stream (partial text is kept)', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('half an answ'));
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(textOf(r.events), 'half an answ');
      expect(r.error!.error.kind, LlmErrorKind.badStream);
    });

    test('finish_reason without [DONE] is fine', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('done'));
        req.response.write(sse('', finish: 'stop'));
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error, isNull);
      expect(textOf(r.events), 'done');
    });

    test('no text at all -> emptyResponse; finish_reason length is reported as cut off', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('', finish: 'length'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      expect((await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error.kind, LlmErrorKind.emptyResponse);

      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('cut'));
        req.response.write(sse('', finish: 'length'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect((r.events.last as LlmFinished).cutOff, isTrue);
    });

    test('garbage data is a bad stream', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write('data: <html>not json</html>\n\n');
        await req.response.close();
      };
      expect((await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key))).error!.error.kind, LlmErrorKind.badStream);
    });

    test('a server that ignores stream:true and answers with one JSON body still works', () async {
      fake.handler = (req, _) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {'index': 0, 'message': {'role': 'assistant', 'content': 'whole answer'}, 'finish_reason': 'stop'},
          ],
        }));
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error, isNull);
      expect(textOf(r.events), 'whole answer');
    });

    test('the answer is cut at 32 KB, marked truncated, and the request is dropped', () async {
      final connectionClosed = Completer<void>();
      fake.handler = (req, _) async {
        startStream(req.response);
        final socketDone = req.response.done.then<void>((_) {}, onError: (Object _) {});
        socketDone.then((_) => connectionClosed.complete());
        // 4 KB deltas, 20 of them = 80 KB; a stuck client would take them all.
        for (var i = 0; i < 20; i++) {
          req.response.write(sse('é' * 2048)); // 2-byte characters
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error, isNull);
      final text = textOf(r.events);
      expect(utf8.encode(text).length, lessThanOrEqualTo(Limits.maxLlmStreamBytes));
      expect(utf8.encode(text).length, greaterThan(Limits.maxLlmStreamBytes - 4));
      expect(text.runes.every((c) => c == 0xe9), isTrue, reason: 'never cut inside a character');
      final fin = r.events.last as LlmFinished;
      expect(fin.truncated, isTrue);
      expect(fin.cutOff, isTrue);
      await connectionClosed.future.timeout(const Duration(seconds: 5));
    });
  });

  group('cancel and timeouts', () {
    test('cancelling the subscription aborts the request (the server sees the connection close)', () async {
      final serverSawClose = Completer<void>();
      fake.handler = (req, _) async {
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.listen((_) {}, onDone: serverSawClose.complete, onError: (Object _) => serverSawClose.complete());
        socket.write('HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n');
        socket.write(sse('first '));
        await socket.flush();
      };
      final got = Completer<void>();
      final sub = client().stream(requestFor(fake.baseUrl), readApiKey: key).listen((e) {
        if (e is LlmTextDelta && !got.isCompleted) got.complete();
      });
      await got.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      await serverSawClose.future.timeout(const Duration(seconds: 5));
    });

    test('cancelling before the response arrives also aborts', () async {
      final serverSawClose = Completer<void>();
      final requestSeen = Completer<void>();
      fake.handler = (req, _) async {
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.listen((_) {}, onDone: serverSawClose.complete, onError: (Object _) => serverSawClose.complete());
        requestSeen.complete(); // never answers
      };
      final sub = client().stream(requestFor(fake.baseUrl), readApiKey: key).listen((_) {});
      await requestSeen.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      await serverSawClose.future.timeout(const Duration(seconds: 5));
    });

    test('no response headers within the first-byte timeout -> timeout', () async {
      fake.handler = (req, _) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await req.response.close();
      };
      final c = client(timeouts: const LlmTimeouts(firstByte: Duration(milliseconds: 150)));
      final r = await collect(c.stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error!.error.kind, LlmErrorKind.timeout);
    });

    test('a stalled stream (no bytes for the first-byte timeout) -> timeout, keeping the text so far', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('so far'));
        await req.response.flush();
        await Future<void>.delayed(const Duration(seconds: 2));
        await req.response.close();
      };
      final c = client(timeouts: const LlmTimeouts(firstByte: Duration(milliseconds: 200)));
      final r = await collect(c.stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(textOf(r.events), 'so far');
      expect(r.error!.error.kind, LlmErrorKind.timeout);
    });

    test('the total timeout cuts a stream that keeps trickling', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        for (var i = 0; i < 100; i++) {
          req.response.write(': keep-alive\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await req.response.close();
      };
      final c = client(timeouts: const LlmTimeouts(firstByte: Duration(seconds: 5), total: Duration(milliseconds: 400)));
      final stopwatch = Stopwatch()..start();
      final r = await collect(c.stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error!.error.kind, LlmErrorKind.timeout);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('total stream cap and finish reasons', () {
    test('reasoning-only chunks and comments are cut at the total byte cap -> badStream', () async {
      final closed = Completer<void>();
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.done.then<void>((_) => closed.complete(), onError: (Object _) => closed.complete());
        final reasoning = 'data: ${jsonEncode({
          'choices': [
            {'index': 0, 'delta': {'reasoning': 'x' * 60000}, 'finish_reason': null},
          ],
        })}\n\n';
        for (var i = 0; i < 40; i++) {
          req.response.write(reasoning); // ~2.4 MB, no answer text at all
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      expect(r.error!.error.kind, LlmErrorKind.badStream);
      expect(r.events.whereType<LlmFinished>(), isEmpty);
      await closed.future.timeout(const Duration(seconds: 5));
    });

    test('finish_reason content_filter is reported as filtered, not complete', () async {
      fake.handler = (req, _) async {
        startStream(req.response);
        req.response.write(sse('Partial'));
        req.response.write(sse('', finish: 'content_filter'));
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      };
      final r = await collect(client().stream(requestFor(fake.baseUrl), readApiKey: key));
      final fin = r.events.last as LlmFinished;
      expect(fin.filtered, isTrue);
      expect(fin.complete, isFalse);
      expect(fin.cutOff, isFalse);
      expect(const LlmFinished(finishReason: 'stop').complete, isTrue);
      expect(const LlmFinished(finishReason: 'length').complete, isFalse);
      expect(const LlmFinished(truncated: true).complete, isFalse);
    });
  });

  group('testConnection', () {
    test('the 180 s total timer maps to timeout, not offline', () async {
      fake.handler = (req, _) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        await req.response.close();
      };
      final c = client(timeouts: const LlmTimeouts(firstByte: Duration(seconds: 5), total: Duration(milliseconds: 200)));
      final e = await c.testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key);
      expect(e!.kind, LlmErrorKind.timeout);
    });

    test('success: tiny non-streamed request with the key and the model', () async {
      fake.handler = (req, _) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {'index': 0, 'message': {'role': 'assistant', 'content': 'OK'}, 'finish_reason': 'stop'},
          ],
        }));
        await req.response.close();
      };
      final ok = await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key);
      expect(ok, isNull);
      final r = fake.requests.single;
      expect(r.json['stream'], false);
      expect(r.json['model'], 'm');
      expect(r.headers['authorization'], 'Bearer $secret');
      expect(r.json.containsKey('max_tokens'), isFalse);
      expect(r.body, isNot(contains(secret)));
    });

    test('a token limit mode is honoured and capped at 16 tokens for the probe', () async {
      fake.handler = (req, _) async {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'choices': [
            {'index': 0, 'message': {'content': ''}, 'finish_reason': 'length'},
          ],
        }));
        await req.response.close();
      };
      final ok = await client().testConnection(
        LlmConfig(baseUrl: fake.baseUrl, model: 'm', tokenLimitMode: TokenLimitMode.maxCompletionTokens, tokenLimit: 2000),
        readApiKey: key,
      );
      expect(ok, isNull, reason: 'an empty reply with finish_reason length still proves the connection');
      expect(fake.requests.single.json['max_completion_tokens'], 16);
    });

    test('failures: wrong key, wrong model, no model, blocked URL, wrong path', () async {
      fake.handler = (req, _) async {
        req.response.statusCode = 401;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': {'message': 'Incorrect API key provided: $secret', 'code': 'invalid_api_key'}}));
        await req.response.close();
      };
      final unauthorized = await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key);
      expect(unauthorized!.kind, LlmErrorKind.unauthorized);
      expect(unauthorized.detail, isNot(contains(secret)));

      fake.handler = (req, _) async {
        req.response.statusCode = 404;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': {'message': 'model "m" not found, try pulling it first', 'type': 'api_error'}}));
        await req.response.close();
      };
      expect((await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key))!.kind, LlmErrorKind.modelNotFound);

      expect((await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: '  '), readApiKey: key))!.kind, LlmErrorKind.noModel);
      expect((await client().testConnection(const LlmConfig(baseUrl: 'http://example.com/v1', model: 'm'), readApiKey: key))!.kind, LlmErrorKind.cleartextBlocked);

      fake.handler = (req, _) async {
        req.response.statusCode = 404;
        req.response.write('404 page not found');
        await req.response.close();
      };
      expect((await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key))!.kind, LlmErrorKind.endpointNotFound);
    });

    test('a 200 that is not a chat completion is a bad stream', () async {
      fake.handler = (req, _) async {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html>captive portal</html>');
        await req.response.close();
      };
      expect((await client().testConnection(LlmConfig(baseUrl: fake.baseUrl, model: 'm'), readApiKey: key))!.kind, LlmErrorKind.badStream);
    });
  });

  test('a client that throws never leaks the key through the error', () async {
    final c = LlmClient(
      httpClient: () => _ThrowingClient('connection failed while sending Authorization: Bearer $secret'),
    );
    final r = await collect(c.stream(requestFor('https://api.example.com/v1'), readApiKey: key));
    expect(r.error!.error.kind, LlmErrorKind.offline);
    expect(r.error.toString(), isNot(contains(secret)));
    expect(r.error!.error.toString(), isNot(contains(secret)));
    expect(r.error!.error.detail, isNull);
  });
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.message);

  final String message;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Future.error(http.ClientException(message));
}
