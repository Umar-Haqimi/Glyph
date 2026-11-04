import 'dart:convert';

import 'llm_error.dart';
import 'sse_decoder.dart';

/// One decoded item of a chat completions stream.
sealed class ChatItem {
  const ChatItem();
}

final class ChatDelta extends ChatItem {
  const ChatDelta(this.text);

  final String text;
}

final class ChatFinish extends ChatItem {
  const ChatFinish(this.reason);

  final String reason;
}

/// `data: [DONE]`.
final class ChatDone extends ChatItem {
  const ChatDone();
}

/// An error the provider reported inside the stream.
final class ChatFailure extends ChatItem {
  const ChatFailure(this.error);

  final LlmError error;
}

/// Reads OpenAI-style streamed chunks (`choices[0].delta.content`,
/// `finish_reason`, `[DONE]`, usage-only chunks, error chunks).
///
/// Used for OpenAI, OpenRouter and Ollama / LM Studio / llama.cpp (their
/// `/v1/chat/completions` streams share this shape). Reasoning text
/// (`delta.reasoning`, `reasoning_content`) is ignored: only `content` is
/// shown. Returns the items of one event (a chunk can carry both text and a
/// finish reason).
List<ChatItem> parseChatEvent(SseEvent event) {
  final data = event.data.trim();
  if (data.isEmpty) return const [];
  if (data == '[DONE]') return const [ChatDone()];

  Object? json;
  try {
    json = jsonDecode(data);
  } on FormatException {
    if (event.event == 'error') return [ChatFailure(LlmError(LlmErrorKind.badStream, detail: _clip(data)))];
    throw const LlmException(LlmError(LlmErrorKind.badStream));
  }
  if (json is! Map<String, dynamic>) {
    throw const LlmException(LlmError(LlmErrorKind.badStream));
  }
  if (event.event == 'error' && json['error'] == null) {
    return [ChatFailure(ErrorMapper.fromStreamError(json))];
  }
  if (json['error'] != null) return [ChatFailure(ErrorMapper.fromStreamError(json['error']))];

  final out = <ChatItem>[];
  final choices = json['choices'];
  if (choices is List && choices.isNotEmpty && choices.first is Map<String, dynamic>) {
    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'];
    if (delta is Map<String, dynamic>) {
      final content = delta['content'];
      if (content is String && content.isNotEmpty) out.add(ChatDelta(content));
    }
    final finish = choice['finish_reason'];
    if (finish is String && finish.isNotEmpty) {
      if (finish == 'error') {
        // OpenRouter: a mid-stream failure ends with finish_reason "error".
        return [...out, const ChatFailure(LlmError(LlmErrorKind.badStream))];
      }
      out.add(ChatFinish(finish));
    }
  }
  return out;
}

/// The text of a complete (non-streamed) response, or the error it carries.
/// Throws [LlmException] when the body is not a chat completion.
({String text, String? finishReason}) parseCompleteResponse(String body) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw const LlmException(LlmError(LlmErrorKind.badStream));
  }
  if (json is! Map<String, dynamic>) throw const LlmException(LlmError(LlmErrorKind.badStream));
  if (json['error'] != null) throw LlmException(ErrorMapper.fromStreamError(json['error']));
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map<String, dynamic>) {
    throw const LlmException(LlmError(LlmErrorKind.badStream));
  }
  final choice = choices.first as Map<String, dynamic>;
  final message = choice['message'];
  final content = message is Map<String, dynamic> ? message['content'] : null;
  final finish = choice['finish_reason'];
  return (text: content is String ? content : '', finishReason: finish is String ? finish : null);
}

String _clip(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
