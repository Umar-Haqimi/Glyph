import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../util/limits.dart';

/// The failure kinds of an explanation / summary / connection test (SPEC 4
/// "ExplainRequest", plus the extra cases the app needs to say something
/// useful). Every kind has its own copy in `app_en.arb`.
enum LlmErrorKind {
  /// SPEC `noKey`: a key is needed and none is stored.
  noKey,

  /// No model name entered.
  noModel,

  /// The base URL is unusable (not a URL, wrong scheme, credentials ...).
  invalidUrl,

  /// SPEC `unauthorized` (401, 403).
  unauthorized,

  /// SPEC `modelNotFound` (404 with an error body, or a model error).
  modelNotFound,

  /// 404 / redirect without a provider error body: usually a wrong base URL.
  endpointNotFound,

  /// SPEC `rateLimited` (429).
  rateLimited,

  /// SPEC `quotaExceeded` (429 `insufficient_quota`, OpenRouter 402).
  quotaExceeded,

  /// SPEC `unsupportedParam` (400 `unsupported_parameter` / `unsupported_value`).
  unsupportedParam,

  /// Any other 4xx the provider sent.
  badRequest,

  /// SPEC `cleartextBlocked`.
  cleartextBlocked,

  /// SPEC `offline`.
  offline,

  /// TLS handshake / certificate failure.
  tls,

  /// SPEC `timeout`.
  timeout,

  /// SPEC `server` (5xx).
  server,

  /// SPEC `badStream`.
  badStream,

  /// The model finished without any text.
  emptyResponse,

  /// The move has no engine data yet (Explain before the analysis reached it).
  notAnalysed,
}

/// A failed LLM call, in user-facing terms. [detail] is the provider's own
/// message (trimmed, never containing the API key); the UI shows it only as
/// secondary text.
class LlmError {
  const LlmError(this.kind, {this.status, this.param, this.detail});

  final LlmErrorKind kind;

  /// HTTP status, when there was one.
  final int? status;

  /// The offending request parameter for [LlmErrorKind.unsupportedParam].
  final String? param;
  final String? detail;

  @override
  String toString() => 'LlmError(${kind.name}${status == null ? '' : ' $status'}${param == null ? '' : ' param=$param'})';
}

/// Thrown into the event stream of the client for every [LlmError].
class LlmException implements Exception {
  const LlmException(this.error);

  final LlmError error;

  @override
  String toString() => 'LlmException(${error.kind.name})';
}

/// Turns HTTP statuses, provider error bodies, mid-stream error events and
/// transport exceptions into [LlmError]s (SPEC 4 and 7.2).
///
/// Provider shapes handled:
/// * OpenAI / Ollama / LM Studio: `{"error": {"message", "type", "param", "code"}}`
/// * OpenRouter: `{"error": {"code": 402, "message": "...", "metadata": {...}}}`
///   (HTTP errors and mid-stream error chunks)
/// * `{"error": "text"}` (older servers) and plain-text bodies.
abstract final class ErrorMapper {
  /// An error response ([status] is not 2xx) with [body].
  static LlmError fromHttp(int status, String body) {
    final err = _errorObject(body);
    final code = _s(err?['code'])?.toLowerCase();
    final type = _s(err?['type'])?.toLowerCase();
    final message = _message(err, body);
    final param = _s(err?['param']);

    LlmError make(LlmErrorKind kind, {String? p}) => LlmError(kind, status: status, param: p, detail: message);

    if (status == 401 || status == 403) return make(LlmErrorKind.unauthorized);
    if (status == 402 || _isQuota(code, type)) return make(LlmErrorKind.quotaExceeded);
    if (status == 429) return make(LlmErrorKind.rateLimited);
    if (status == 408 || (status == 504 && _mentionsTimeout(message))) return make(LlmErrorKind.timeout);
    if (status == 404) {
      return make(err == null ? LlmErrorKind.endpointNotFound : LlmErrorKind.modelNotFound);
    }
    if (status >= 300 && status < 400) return make(LlmErrorKind.endpointNotFound);
    if (_isUnsupported(code, type)) return make(LlmErrorKind.unsupportedParam, p: param ?? _paramFromMessage(message));
    if (code == 'model_not_found' || _looksLikeModelError(status, message)) return make(LlmErrorKind.modelNotFound);
    if (status >= 500) return make(LlmErrorKind.server);
    if (status >= 400) return make(LlmErrorKind.badRequest);
    return make(LlmErrorKind.badStream);
  }

  /// An error object that arrived inside a 200 stream (`data: {"error": ...}`
  /// or `event: error`). [error] is the decoded `error` value (a map or text).
  static LlmError fromStreamError(Object? error) {
    final map = error is Map<String, dynamic> ? error : null;
    final message = map == null ? _trim(error?.toString()) : _trim(_s(map['message']));
    final rawCode = map?['code'];
    final code = _s(rawCode)?.toLowerCase();
    final type = _s(map?['type'])?.toLowerCase();
    // OpenRouter puts the HTTP status in `code`.
    final status = rawCode is int ? rawCode : int.tryParse(code ?? '');
    if (status != null) {
      return fromHttp(status, jsonEncode({'error': map ?? {'message': message}}));
    }
    LlmError make(LlmErrorKind kind, {String? p}) => LlmError(kind, param: p, detail: message);
    if (_isQuota(code, type)) return make(LlmErrorKind.quotaExceeded);
    if (code == 'invalid_api_key' || code == 'authentication_error' || type == 'authentication_error') {
      return make(LlmErrorKind.unauthorized);
    }
    if (code == 'rate_limit_exceeded' || type == 'rate_limit_error' || code == 'rate_limited') {
      return make(LlmErrorKind.rateLimited);
    }
    if (code == 'model_not_found') return make(LlmErrorKind.modelNotFound);
    if (_isUnsupported(code, type)) {
      return make(LlmErrorKind.unsupportedParam, p: _s(map?['param']) ?? _paramFromMessage(message));
    }
    if (code == 'server_error' || type == 'server_error' || type == 'api_error' || code == 'overloaded') {
      return make(LlmErrorKind.server);
    }
    return make(LlmErrorKind.badStream);
  }

  /// A transport failure: no connection, DNS, TLS, timeout, a cleartext block
  /// of the platform. Matches on type names and messages so the core needs no
  /// `dart:io`.
  static LlmError fromException(Object error) {
    if (error is LlmException) return error.error;
    if (error is TimeoutException) return const LlmError(LlmErrorKind.timeout);
    final type = error.runtimeType.toString();
    final text = error.toString().toLowerCase();
    if (text.contains('cleartext')) return const LlmError(LlmErrorKind.cleartextBlocked);
    if (type.contains('Handshake') || type.contains('Tls') || text.contains('certificate') || text.contains('handshake')) {
      return const LlmError(LlmErrorKind.tls);
    }
    if (text.contains('timed out') || text.contains('timeout')) return const LlmError(LlmErrorKind.timeout);
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
      return const LlmError(LlmErrorKind.offline);
    }
    return const LlmError(LlmErrorKind.badStream);
  }

  // --- helpers ---------------------------------------------------------------

  static Map<String, dynamic>? _errorObject(String body) {
    final t = body.trim();
    if (t.isEmpty || !(t.startsWith('{') || t.startsWith('['))) return null;
    try {
      final decoded = jsonDecode(t);
      Object? err = decoded is Map<String, dynamic> ? decoded['error'] : null;
      if (err == null && decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        err = (decoded.first as Map<String, dynamic>)['error'];
      }
      if (err is Map<String, dynamic>) return err;
      if (err is String) return {'message': err};
      // Ollama's native shape / FastAPI: {"detail": "..."} or {"message": "..."}.
      if (decoded is Map<String, dynamic>) {
        final m = decoded['message'] ?? decoded['detail'];
        if (m is String) return {'message': m};
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _message(Map<String, dynamic>? err, String body) {
    final fromObject = _s(err?['message']);
    if (fromObject != null) return _trim(fromObject);
    return err == null ? _trim(body) : null;
  }

  static String? _trim(String? s) {
    if (s == null) return null;
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length > 300 ? '${t.substring(0, 300)}…' : t;
  }

  static String? _s(Object? v) => v?.toString();

  static bool _isQuota(String? code, String? type) =>
      code == 'insufficient_quota' || type == 'insufficient_quota' || code == 'billing_hard_limit_reached';

  static bool _isUnsupported(String? code, String? type) =>
      code == 'unsupported_parameter' || code == 'unsupported_value' || type == 'unsupported_parameter';

  static bool _mentionsTimeout(String? m) => m != null && m.toLowerCase().contains('timeout');

  /// `Unsupported parameter: 'max_tokens' is not supported ...`
  static String? _paramFromMessage(String? message) {
    if (message == null) return null;
    final m = RegExp(r"""['"`]([A-Za-z_][A-Za-z0-9_.]*)['"`]""").firstMatch(message);
    return m?.group(1);
  }

  /// 400 / 422 bodies that are about the model name (OpenRouter: "x is not a
  /// valid model ID"; some servers: "model 'x' does not exist").
  static bool _looksLikeModelError(int status, String? message) {
    if (status != 400 && status != 422) return false;
    final m = message?.toLowerCase();
    if (m == null || !m.contains('model')) return false;
    return m.contains('not a valid') ||
        m.contains('does not exist') ||
        m.contains('not found') ||
        m.contains('invalid model') ||
        m.contains('unknown model');
  }

  /// Reads at most [Limits.maxLlmErrorBodyBytes] of [bytes] as text (the rest
  /// of the stream is dropped).
  static Future<String> readBody(Stream<List<int>> bytes) {
    final builder = BytesBuilder(copy: false);
    final done = Completer<String>();
    late final StreamSubscription<List<int>> sub;
    String result() {
      final all = builder.takeBytes();
      final slice = all.length > Limits.maxLlmErrorBodyBytes ? all.sublist(0, Limits.maxLlmErrorBodyBytes) : all;
      return utf8.decode(slice, allowMalformed: true);
    }

    sub = bytes.listen(
      (chunk) {
        builder.add(chunk);
        if (builder.length >= Limits.maxLlmErrorBodyBytes && !done.isCompleted) {
          unawaited(sub.cancel());
          done.complete(result());
        }
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(result());
      },
      cancelOnError: true,
    );
    return done.future;
  }
}
