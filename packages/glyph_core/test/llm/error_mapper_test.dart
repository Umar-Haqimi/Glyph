import 'dart:async';
import 'dart:convert';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _SocketException implements Exception {
  _SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}

class _HandshakeException implements Exception {
  @override
  String toString() => 'HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)';
}

String err(Map<String, Object?> e) => jsonEncode({'error': e});

void main() {
  group('HTTP statuses and bodies', () {
    final cases = <String, (int, String, LlmErrorKind)>{
      '401': (401, err({'message': 'x', 'code': 'invalid_api_key'}), LlmErrorKind.unauthorized),
      '401 plain text': (401, 'Unauthorized', LlmErrorKind.unauthorized),
      '403': (403, err({'message': 'forbidden'}), LlmErrorKind.unauthorized),
      '404 with error body': (404, err({'message': 'model not found'}), LlmErrorKind.modelNotFound),
      '404 model_not_found code': (404, err({'code': 'model_not_found', 'message': 'nope'}), LlmErrorKind.modelNotFound),
      '404 plain text (wrong URL)': (404, '404 page not found', LlmErrorKind.endpointNotFound),
      '404 empty': (404, '', LlmErrorKind.endpointNotFound),
      '404 html': (404, '<html>Not Found</html>', LlmErrorKind.endpointNotFound),
      '301 redirect': (301, '', LlmErrorKind.endpointNotFound),
      '307 redirect': (307, '', LlmErrorKind.endpointNotFound),
      '429': (429, err({'message': 'slow down', 'code': 'rate_limit_exceeded'}), LlmErrorKind.rateLimited),
      '429 plain': (429, 'Too Many Requests', LlmErrorKind.rateLimited),
      '429 insufficient_quota code': (429, err({'code': 'insufficient_quota', 'type': 'insufficient_quota'}), LlmErrorKind.quotaExceeded),
      '429 insufficient_quota type only': (429, err({'type': 'insufficient_quota'}), LlmErrorKind.quotaExceeded),
      '402 OpenRouter credits': (402, err({'message': 'Insufficient credits', 'code': 402}), LlmErrorKind.quotaExceeded),
      '400 unsupported_parameter': (400, err({'code': 'unsupported_parameter', 'param': 'max_tokens', 'message': 'm'}), LlmErrorKind.unsupportedParam),
      '400 unsupported_value': (400, err({'code': 'unsupported_value', 'param': 'temperature'}), LlmErrorKind.unsupportedParam),
      '400 other': (400, err({'message': 'messages too long'}), LlmErrorKind.badRequest),
      '400 context length': (400, err({'code': 'context_length_exceeded', 'message': 'maximum context length'}), LlmErrorKind.badRequest),
      '400 OpenRouter invalid model': (400, err({'message': 'x is not a valid model ID', 'code': 400}), LlmErrorKind.modelNotFound),
      '400 model does not exist': (400, err({'message': "model 'x' does not exist"}), LlmErrorKind.modelNotFound),
      '422': (422, err({'message': 'bad field'}), LlmErrorKind.badRequest),
      '408': (408, '', LlmErrorKind.timeout),
      '500': (500, err({'message': 'oops', 'type': 'server_error'}), LlmErrorKind.server),
      '502 html': (502, '<html>Bad Gateway</html>', LlmErrorKind.server),
      '503': (503, '', LlmErrorKind.server),
      '529 overloaded': (529, err({'type': 'overloaded_error'}), LlmErrorKind.server),
      'error as plain string': (400, jsonEncode({'error': 'bad thing'}), LlmErrorKind.badRequest),
      'FastAPI detail': (400, jsonEncode({'detail': 'bad thing'}), LlmErrorKind.badRequest),
      'unparseable json': (500, '{"error": ', LlmErrorKind.server),
    };
    cases.forEach((name, c) {
      test(name, () {
        final e = ErrorMapper.fromHttp(c.$1, c.$2);
        expect(e.kind, c.$3);
        expect(e.status, c.$1);
      });
    });

    test('the offending parameter comes from "param", else from the message', () {
      expect(ErrorMapper.fromHttp(400, err({'code': 'unsupported_parameter', 'param': 'max_tokens'})).param, 'max_tokens');
      expect(
        ErrorMapper.fromHttp(400, err({'code': 'unsupported_parameter', 'message': "Unsupported parameter: 'max_completion_tokens' is not supported."})).param,
        'max_completion_tokens',
      );
    });

    test('detail is the provider message, whitespace-collapsed and capped', () {
      final long = 'word ' * 200;
      final e = ErrorMapper.fromHttp(400, err({'message': '  two\n\nlines  $long'}));
      expect(e.detail, startsWith('two lines word'));
      expect(e.detail!.length, lessThanOrEqualTo(301));
    });

    test('readBody caps the amount it reads', () async {
      final big = Stream.fromIterable([List.filled(40 * 1024, 65), List.filled(40 * 1024, 66), List.filled(40 * 1024, 67)]);
      final text = await ErrorMapper.readBody(big);
      expect(text.length, Limits.maxLlmErrorBodyBytes);
      expect(text, isNot(contains('C')));
    });
  });

  group('errors inside a 200 stream', () {
    test('OpenAI server_error', () {
      expect(ErrorMapper.fromStreamError({'message': 'm', 'type': 'server_error', 'code': null}).kind, LlmErrorKind.server);
    });
    test('OpenRouter numeric code is the HTTP status', () {
      expect(ErrorMapper.fromStreamError({'code': 429, 'message': 'x'}).kind, LlmErrorKind.rateLimited);
      expect(ErrorMapper.fromStreamError({'code': 402, 'message': 'x'}).kind, LlmErrorKind.quotaExceeded);
      expect(ErrorMapper.fromStreamError({'code': 502, 'message': 'x'}).kind, LlmErrorKind.server);
      expect(ErrorMapper.fromStreamError({'code': '401', 'message': 'x'}).kind, LlmErrorKind.unauthorized);
    });
    test('OpenRouter string codes', () {
      expect(ErrorMapper.fromStreamError({'code': 'server_error', 'message': 'Provider disconnected unexpectedly'}).kind, LlmErrorKind.server);
      expect(ErrorMapper.fromStreamError({'code': 'rate_limit_exceeded'}).kind, LlmErrorKind.rateLimited);
      expect(ErrorMapper.fromStreamError({'code': 'insufficient_quota'}).kind, LlmErrorKind.quotaExceeded);
      expect(ErrorMapper.fromStreamError({'code': 'invalid_api_key'}).kind, LlmErrorKind.unauthorized);
      expect(ErrorMapper.fromStreamError({'code': 'model_not_found'}).kind, LlmErrorKind.modelNotFound);
      expect(ErrorMapper.fromStreamError({'code': 'unsupported_parameter', 'param': 'x'}).kind, LlmErrorKind.unsupportedParam);
    });
    test('unknown error shapes are badStream with the text kept', () {
      final e = ErrorMapper.fromStreamError('something odd');
      expect(e.kind, LlmErrorKind.badStream);
      expect(e.detail, 'something odd');
      expect(ErrorMapper.fromStreamError({'message': 'm'}).kind, LlmErrorKind.badStream);
    });
  });

  group('transport failures', () {
    test('timeouts', () {
      expect(ErrorMapper.fromException(TimeoutException('x')).kind, LlmErrorKind.timeout);
      expect(ErrorMapper.fromException(_SocketException('Connection timed out')).kind, LlmErrorKind.timeout);
    });
    test('no connection', () {
      for (final m in [
        'Failed host lookup: api.openai.com',
        'Connection refused',
        'Network is unreachable',
        'Connection reset by peer',
        'Connection closed before full header was received',
        'No route to host',
      ]) {
        expect(ErrorMapper.fromException(_SocketException(m)).kind, LlmErrorKind.offline, reason: m);
      }
      expect(ErrorMapper.fromException(http.ClientException('whatever')).kind, LlmErrorKind.offline);
    });
    test('Android cleartext block', () {
      expect(
        ErrorMapper.fromException(http.ClientException('Cleartext HTTP traffic to 192.168.1.5 not permitted')).kind,
        LlmErrorKind.cleartextBlocked,
      );
    });
    test('TLS', () {
      expect(ErrorMapper.fromException(_HandshakeException()).kind, LlmErrorKind.tls);
    });
    test('LlmException passes through; anything else is badStream', () {
      expect(ErrorMapper.fromException(const LlmException(LlmError(LlmErrorKind.quotaExceeded))).kind, LlmErrorKind.quotaExceeded);
      expect(ErrorMapper.fromException(StateError('x')).kind, LlmErrorKind.badStream);
    });
  });

  test('every kind has a distinct name (copy keys in the app depend on it)', () {
    expect({for (final k in LlmErrorKind.values) k.name}.length, LlmErrorKind.values.length);
  });
}
