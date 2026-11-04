import 'dart:convert';

/// Which parameter limits the length of the answer (SPEC trap 12). Newer
/// OpenAI models reject `max_tokens`, some compatible servers reject
/// `max_completion_tokens`, so the default is to send neither.
enum TokenLimitMode {
  none('none'),
  maxTokens('max_tokens'),
  maxCompletionTokens('max_completion_tokens');

  const TokenLimitMode(this.parameter);

  /// The JSON field name, or `none`.
  final String parameter;

  static TokenLimitMode fromName(String? name) =>
      TokenLimitMode.values.where((m) => m.name == name).firstOrNull ?? TokenLimitMode.none;
}

/// Where and how to call the model. The API key is **not** part of this: it
/// is read from the secret store for each request and passed separately.
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.model,
    this.tokenLimitMode = TokenLimitMode.none,
    this.tokenLimit = 1024,
  });

  /// As entered; validated by `BaseUrlPolicy` before every request.
  final String baseUrl;
  final String model;
  final TokenLimitMode tokenLimitMode;
  final int tokenLimit;

  @override
  bool operator ==(Object other) =>
      other is LlmConfig &&
      other.baseUrl == baseUrl &&
      other.model == model &&
      other.tokenLimitMode == tokenLimitMode &&
      other.tokenLimit == tokenLimit;

  @override
  int get hashCode => Object.hash(baseUrl, model, tokenLimitMode, tokenLimit);
}

enum ChatRole { system, user }

class ChatMessage {
  const ChatMessage(this.role, this.content);

  final ChatRole role;
  final String content;

  Map<String, String> toJson() => {'role': role.name, 'content': content};
}

/// A chat completions request. [toJson] is **exactly** the body that is
/// sent, and what "View prompt" shows: messages, model, `stream` and the
/// optional token limit; never `temperature`, never the API key.
class LlmRequest {
  const LlmRequest({required this.config, required this.messages, this.stream = true});

  final LlmConfig config;
  final List<ChatMessage> messages;
  final bool stream;

  Map<String, Object?> toJson() => {
        'model': config.model,
        'messages': [for (final m in messages) m.toJson()],
        'stream': stream,
        if (config.tokenLimitMode != TokenLimitMode.none) config.tokenLimitMode.parameter: config.tokenLimit,
      };

  /// The request body as sent over the wire.
  String body() => jsonEncode(toJson());

  /// The body with indentation, for display.
  String prettyBody() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// What the client emits while a response streams in. Failures are thrown
/// into the stream as `LlmException`.
sealed class LlmEvent {
  const LlmEvent();
}

/// A piece of the answer text.
final class LlmTextDelta extends LlmEvent {
  const LlmTextDelta(this.text);

  final String text;

  @override
  String toString() => 'LlmTextDelta($text)';
}

/// The answer is complete.
final class LlmFinished extends LlmEvent {
  const LlmFinished({this.finishReason, this.truncated = false});

  /// The provider's `finish_reason` (`stop`, `length`, ...), if it sent one.
  final String? finishReason;

  /// Glyph stopped reading because the answer reached `Limits.maxLlmStreamBytes`.
  final bool truncated;

  /// The text ends early: our cap, or the model's token limit.
  bool get cutOff => truncated || finishReason == 'length';

  @override
  String toString() => 'LlmFinished(${finishReason ?? '-'}${truncated ? ', truncated' : ''})';
}
