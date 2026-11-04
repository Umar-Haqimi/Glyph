// Regenerates the SYNTHETIC SSE / HTTP-error vectors in test/vectors/sse/.
//
// No API keys were available in M0-M6, so these are NOT captures: they are
// hand-built from each provider's documented streaming format (OpenAI chat
// completion chunks, OpenRouter's ": OPENROUTER PROCESSING" comments and
// native_finish_reason / usage chunk, Ollama's OpenAI-compatible /v1 stream,
// the providers' documented error bodies). Every file says so. Replace them
// with real captures using the curl commands in docs/m0/VECTORS.md section 4
// when keys are at hand; the tests and manifest stay the same.
//
//   cd packages/glyph_core && dart run tool/gen_sse_fixtures.dart
import 'dart:convert';
import 'dart:io';

const outDir = 'test/vectors/sse';

/// The answer every success stream spells out (non-ASCII on purpose: the
/// tests split the bytes at every position, including inside characters).
const deltas = <String>[
  'Nx', 'e5', ' loses', ' a', ' knight', ' —', ' after', ' ...', 'Nxe5', ',', ' you', ' are', ' three', ' points',
  ' down', ' (', '日本語', ' café', ' ♞', ').', '\n', 'Better', ' was', ' d3', '.',
];
final fullText = deltas.join();

const synthetic = 'SYNTHETIC vector: hand-built from the documented format, NOT a real capture (docs/m0/VECTORS.md section 4)';

final manifest = <Map<String, Object?>>[];

String chunk(Map<String, Object?> m) => jsonEncode(m);

void writeStream(String file, String body, {required String? finish, String? errorKind, String? text, String? note}) {
  File('$outDir/$file').writeAsStringSync(body);
  manifest.add({
    'file': file,
    'synthetic': true,
    'type': 'stream',
    'text': errorKind == null || text != null ? (text ?? fullText) : null,
    'finishReason': finish,
    'errorKind': errorKind,
    'note': note,
  });
}

void writeHttp(String file, int status, String reason, String contentType, String body, {required String kind, String? param, String? note}) {
  final out = StringBuffer()
    ..write('HTTP/1.1 $status $reason\r\n')
    ..write('content-type: $contentType\r\n')
    ..write('x-glyph-synthetic: true\r\n')
    ..write('\r\n')
    ..write(body);
  File('$outDir/$file').writeAsStringSync(out.toString());
  manifest.add({'file': file, 'synthetic': true, 'type': 'http', 'status': status, 'errorKind': kind, 'param': param, 'note': note});
}

void main() {
  Directory(outDir).createSync(recursive: true);

  // --- OpenAI ---------------------------------------------------------------
  Map<String, Object?> openai(Map<String, Object?> choice, {Object? usage}) => {
        'id': 'chatcmpl-SYNTHETIC0001',
        'object': 'chat.completion.chunk',
        'created': 1767225600,
        'model': 'gpt-4o-mini-2024-07-18',
        'service_tier': 'default',
        'system_fingerprint': 'fp_SYNTHETIC',
        'choices': [choice],
        'usage': usage,
      };
  final openaiChunks = <String>[
    chunk(openai({'index': 0, 'delta': {'role': 'assistant', 'content': '', 'refusal': null}, 'logprobs': null, 'finish_reason': null})),
    for (final d in deltas)
      chunk(openai({'index': 0, 'delta': {'content': d}, 'logprobs': null, 'finish_reason': null})),
    chunk(openai({'index': 0, 'delta': <String, Object?>{}, 'logprobs': null, 'finish_reason': 'stop'})),
  ];
  String sse(List<String> chunks, {String eol = '\n', String done = 'data: [DONE]'}) =>
      '${chunks.map((c) => 'data: $c$eol$eol').join()}$done$eol$eol';
  writeStream('openai_ok.sse', ': $synthetic\n${sse(openaiChunks)}', finish: 'stop');

  // stream_options.include_usage: a final chunk with empty choices and usage.
  final usageChunk = jsonEncode({
    'id': 'chatcmpl-SYNTHETIC0002',
    'object': 'chat.completion.chunk',
    'created': 1767225600,
    'model': 'gpt-4o-mini-2024-07-18',
    'service_tier': 'default',
    'system_fingerprint': 'fp_SYNTHETIC',
    'choices': <Object?>[],
    'usage': {
      'prompt_tokens': 412,
      'completion_tokens': 38,
      'total_tokens': 450,
      'prompt_tokens_details': {'cached_tokens': 0, 'audio_tokens': 0},
      'completion_tokens_details': {'reasoning_tokens': 0, 'audio_tokens': 0, 'accepted_prediction_tokens': 0, 'rejected_prediction_tokens': 0},
    },
  });
  writeStream('openai_usage.sse', ': $synthetic\n${sse([...openaiChunks, usageChunk])}', finish: 'stop');

  // finish_reason "length": the model hit the token limit.
  final lengthChunks = [
    ...openaiChunks.take(1 + 8),
    chunk(openai({'index': 0, 'delta': <String, Object?>{}, 'logprobs': null, 'finish_reason': 'length'})),
  ];
  writeStream('openai_length.sse', ': $synthetic\n${sse(lengthChunks)}', finish: 'length', text: deltas.take(8).join());

  // Error in the middle of a 200 stream (OpenAI documents `data: {"error": ...}`).
  final midError = jsonEncode({
    'error': {
      'message': 'The server had an error while processing your request. Sorry about that!',
      'type': 'server_error',
      'param': null,
      'code': null,
    },
  });
  writeStream('openai_midstream_error.sse', ': $synthetic\n${sse([...openaiChunks.take(1 + 6), midError], done: '')}',
      finish: null, errorKind: 'server', text: deltas.take(6).join());

  // --- OpenRouter -------------------------------------------------------------
  Map<String, Object?> router(Map<String, Object?> delta, {Object? finish, Object? usage}) => {
        'id': 'gen-SYNTHETIC-1767225600',
        'provider': 'OpenAI',
        'model': 'openai/gpt-4o-mini',
        'object': 'chat.completion.chunk',
        'created': 1767225600,
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish, 'native_finish_reason': finish, 'logprobs': null},
        ],
        'usage': ?usage,
      };
  final routerBody = StringBuffer(': $synthetic\n')
    ..write(': OPENROUTER PROCESSING\n\n')
    ..write(': OPENROUTER PROCESSING\n\n')
    ..write('data: ${chunk(router({'role': 'assistant', 'content': ''}))}\n\n');
  for (var i = 0; i < deltas.length; i++) {
    if (i == 10) routerBody.write(': OPENROUTER PROCESSING\n\n');
    routerBody.write('data: ${chunk(router({'role': 'assistant', 'content': deltas[i]}))}\n\n');
  }
  routerBody
    ..write('data: ${chunk(router({'role': 'assistant', 'content': ''}, finish: 'stop'))}\n\n')
    ..write('data: ${chunk(router({'role': 'assistant', 'content': ''}, usage: {'prompt_tokens': 412, 'completion_tokens': 38, 'total_tokens': 450, 'cost': 0.0000342}))}\n\n')
    ..write('data: [DONE]\n\n');
  writeStream('openrouter_ok.sse', routerBody.toString(), finish: 'stop');

  // OpenRouter mid-stream failure: HTTP 200 already sent, then an error chunk
  // with finish_reason "error" (documented in "Errors / mid-stream").
  final routerError = jsonEncode({
    'id': 'gen-SYNTHETIC-1767225601',
    'provider': 'OpenAI',
    'model': 'openai/gpt-4o-mini',
    'object': 'chat.completion.chunk',
    'created': 1767225600,
    'error': {'code': 'server_error', 'message': 'Provider disconnected unexpectedly'},
    'choices': [
      {'index': 0, 'delta': {'content': ''}, 'finish_reason': 'error'},
    ],
  });
  final routerErr = StringBuffer(': $synthetic\n')
    ..write(': OPENROUTER PROCESSING\n\n');
  for (var i = 0; i < 6; i++) {
    routerErr.write('data: ${chunk(router({'role': 'assistant', 'content': deltas[i]}))}\n\n');
  }
  routerErr.write('data: $routerError\n\n');
  writeStream('openrouter_midstream_error.sse', routerErr.toString(), finish: null, errorKind: 'server', text: deltas.take(6).join());

  // --- Ollama / LM Studio (OpenAI-compatible /v1) -------------------------------
  Map<String, Object?> ollama(Map<String, Object?> delta, {Object? finish}) => {
        'id': 'chatcmpl-123',
        'object': 'chat.completion.chunk',
        'created': 1767225600,
        'model': 'llama3.2',
        'system_fingerprint': 'fp_ollama',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      };
  final ollamaChunks = [
    for (final d in deltas) chunk(ollama({'role': 'assistant', 'content': d})),
    chunk(ollama({'role': 'assistant', 'content': ''}, finish: 'stop')),
  ];
  writeStream('ollama_ok.sse', ': $synthetic\n${sse(ollamaChunks)}', finish: 'stop');

  // A thinking model: `reasoning` deltas first (never shown), then the answer.
  final thinking = [
    for (final t in ['The', ' user', ' wants', ' a', ' short', ' explanation', '.'])
      chunk(ollama({'role': 'assistant', 'content': '', 'reasoning': t})),
    ...ollamaChunks,
  ];
  writeStream('ollama_reasoning.sse', ': $synthetic\n${sse(thinking)}', finish: 'stop');

  // --- Format edge cases (not provider-specific) --------------------------------
  // CRLF line endings, a multi-line data field, `event:` / `id:` / `retry:`
  // fields, keep-alive comments, a lone-CR terminator.
  final half = fullText.length ~/ 2;
  final pretty = const JsonEncoder.withIndent(' ');
  // The same JSON object spread over several `data:` lines (legal SSE).
  final multi = pretty
      .convert(openai({'index': 0, 'delta': {'content': fullText.substring(0, half)}, 'logprobs': null, 'finish_reason': null}))
      .split('\n');
  final crlf = StringBuffer(': $synthetic\r\n')
    ..write('retry: 3000\r\n')
    ..write('\r\n')
    ..write('id: 1\r\nevent: message\r\n${multi.map((l) => 'data: $l').join('\r\n')}\r\n\r\n')
    ..write(': keep-alive\r\n\r\n')
    ..write('data: ${chunk(openai({'index': 0, 'delta': {'content': fullText.substring(half)}, 'logprobs': null, 'finish_reason': null}))}\r\r')
    ..write('data:${chunk(openai({'index': 0, 'delta': <String, Object?>{}, 'logprobs': null, 'finish_reason': 'stop'}))}\r\n\r\n')
    ..write('data: [DONE]\r\n\r\n');
  writeStream('crlf_multiline.sse', crlf.toString(), finish: 'stop', note: 'CRLF, multi-line data, id/event/retry fields, comment, lone CR');

  // --- HTTP error bodies (curl -i style) --------------------------------------------
  writeHttp('openai_401.http', 401, 'Unauthorized', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'Incorrect API key provided: sk-SYNTH***************EKEY. You can find your API key at https://platform.openai.com/account/api-keys.', 'type': 'invalid_request_error', 'param': null, 'code': 'invalid_api_key'}}),
      kind: 'unauthorized');
  writeHttp('openai_404_model.http', 404, 'Not Found', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'The model `gpt-9` does not exist or you do not have access to it.', 'type': 'invalid_request_error', 'param': null, 'code': 'model_not_found'}}),
      kind: 'modelNotFound');
  writeHttp('openai_429_rate.http', 429, 'Too Many Requests', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'Rate limit reached for gpt-4o-mini in organization org-SYNTH on requests per min (RPM): Limit 3, Used 3, Requested 1. Please try again in 20s.', 'type': 'requests', 'param': null, 'code': 'rate_limit_exceeded'}}),
      kind: 'rateLimited');
  writeHttp('openai_429_quota.http', 429, 'Too Many Requests', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'You exceeded your current quota, please check your plan and billing details. For more information on this error, read the docs: https://platform.openai.com/docs/guides/error-codes/api-errors.', 'type': 'insufficient_quota', 'param': null, 'code': 'insufficient_quota'}}),
      kind: 'quotaExceeded');
  writeHttp('openai_400_unsupported_param.http', 400, 'Bad Request', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': "Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.", 'type': 'invalid_request_error', 'param': 'max_tokens', 'code': 'unsupported_parameter'}}),
      kind: 'unsupportedParam', param: 'max_tokens');
  writeHttp('openai_400_unsupported_value.http', 400, 'Bad Request', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': "Unsupported value: 'temperature' does not support 0.2 with this model. Only the default (1) value is supported.", 'type': 'invalid_request_error', 'param': 'temperature', 'code': 'unsupported_value'}}),
      kind: 'unsupportedParam', param: 'temperature');
  writeHttp('openai_500.http', 500, 'Internal Server Error', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'The server had an error while processing your request. Sorry about that!', 'type': 'server_error', 'param': null, 'code': null}}),
      kind: 'server');
  writeHttp('openai_503_html.http', 503, 'Service Unavailable', 'text/html',
      '<html><head><title>503 Service Temporarily Unavailable</title></head><body><center><h1>503</h1></center></body></html>',
      kind: 'server');
  writeHttp('openrouter_401.http', 401, 'Unauthorized', 'application/json',
      jsonEncode({'error': {'message': 'No auth credentials found', 'code': 401}}), kind: 'unauthorized');
  writeHttp('openrouter_402.http', 402, 'Payment Required', 'application/json',
      jsonEncode({'error': {'message': 'Insufficient credits. Add more using https://openrouter.ai/credits', 'code': 402}}),
      kind: 'quotaExceeded');
  writeHttp('openrouter_400_model.http', 400, 'Bad Request', 'application/json',
      jsonEncode({'error': {'message': 'gpt-9 is not a valid model ID', 'code': 400}}), kind: 'modelNotFound');
  writeHttp('openrouter_429.http', 429, 'Too Many Requests', 'application/json',
      jsonEncode({'error': {'message': 'Rate limit exceeded: free-models-per-min.', 'code': 429, 'metadata': {'headers': {'X-RateLimit-Limit': '20', 'X-RateLimit-Remaining': '0'}}}}),
      kind: 'rateLimited');
  writeHttp('ollama_404_model.http', 404, 'Not Found', 'application/json; charset=utf-8',
      jsonEncode({'error': {'message': 'model "llama9" not found, try pulling it first', 'type': 'api_error', 'param': null, 'code': null}}),
      kind: 'modelNotFound');
  writeHttp('ollama_404_path.http', 404, 'Not Found', 'text/plain; charset=utf-8', '404 page not found',
      kind: 'endpointNotFound', note: 'wrong base URL (no /v1)');

  File('$outDir/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'synthetic': true, // true while ANY vector is synthetic
      'note': 'Top-level "synthetic" is true while ANY vector is synthetic; each vector has its own flag (set it to false when replaced by a real capture, docs/RELEASE.md section 2). Do not re-run this generator after replacing files: it overwrites them. $synthetic',
      'vectors': manifest,
    })}\n',
  );
  stdout.writeln('wrote ${manifest.length} vectors to $outDir');
}
