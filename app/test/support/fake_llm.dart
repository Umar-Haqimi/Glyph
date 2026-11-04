import 'dart:async';
import 'dart:convert';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One request the app made to the fake endpoint.
class SeenRequest {
  SeenRequest(this.uri, this.headers, this.body, this.controller);

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final StreamController<List<int>>? controller;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;

  List<Map<String, dynamic>> get messages => (json['messages'] as List).cast<Map<String, dynamic>>();

  /// The user message, the engine-facts JSON.
  Map<String, dynamic> get facts => jsonDecode(messages.last['content'] as String) as Map<String, dynamic>;
}

/// A scripted OpenAI-compatible endpoint behind [client]: no network. Each
/// request is recorded; its response is either an error ([failWith]), a
/// transport failure ([throwOnConnect]) or an event stream that the test
/// feeds with [send] / [finish].
class FakeLlm {
  FakeLlm({LlmTimeouts timeouts = LlmTimeouts.standard}) {
    client = LlmClient(
      httpClient: () => MockClient.streaming((request, bodyStream) async {
        final body = await bodyStream.bytesToString();
        if (throwOnConnect != null) {
          requests.add(SeenRequest(request.url, request.headers, body, null));
          throw throwOnConnect!;
        }
        final fail = failWith;
        if (fail != null) {
          requests.add(SeenRequest(request.url, request.headers, body, null));
          return http.StreamedResponse(Stream.value(utf8.encode(fail.body)), fail.status,
              headers: {'content-type': fail.contentType});
        }
        final ctrl = StreamController<List<int>>(onCancel: () {
          cancelled++;
        });
        requests.add(SeenRequest(request.url, request.headers, body, ctrl));
        return http.StreamedResponse(ctrl.stream, 200, headers: {'content-type': 'text/event-stream'});
      }),
      timeouts: timeouts,
    );
  }

  late final LlmClient client;
  final requests = <SeenRequest>[];

  /// How many response streams the client dropped before they ended.
  int cancelled = 0;
  ({int status, String body, String contentType})? failWith;
  Object? throwOnConnect;

  SeenRequest get last => requests.last;

  static String chunk(String delta, {String? finish}) => 'data: ${jsonEncode({
        'id': 'x',
        'object': 'chat.completion.chunk',
        'choices': [
          {'index': 0, 'delta': delta.isEmpty ? <String, Object?>{} : {'content': delta}, 'finish_reason': finish},
        ],
      })}\n\n';

  /// Streams [delta] to the latest request.
  void send(String delta) => last.controller!.add(utf8.encode(chunk(delta)));

  /// Raw bytes to the latest request.
  void sendRaw(String text) => last.controller!.add(utf8.encode(text));

  /// Ends the latest stream the way a provider does.
  Future<void> finish() async {
    last.controller!.add(utf8.encode('${chunk('', finish: 'stop')}data: [DONE]\n\n'));
    await last.controller!.close();
  }

  /// Ends the latest stream without `[DONE]` or a finish reason.
  Future<void> cutConnection() => last.controller!.close();

  /// Answers every following request with an error body.
  void error(int status, Map<String, Object?> error) =>
      failWith = (status: status, body: jsonEncode({'error': error}), contentType: 'application/json');

  void ok() {
    failWith = null;
    throwOnConnect = null;
  }
}
