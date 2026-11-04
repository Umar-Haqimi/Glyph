import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'base_url_policy.dart';
import 'llm_models.dart';
import 'prompt_builder.dart';

/// The key of an `llm_cache` row (SPEC trap 17).
///
/// `sha256` over an unambiguous (JSON list) encoding of everything that can
/// change the text:
///
/// * SPEC's own fields: `promptVersion`, `kind`, `fenBefore`, `moveUci`,
///   `label`, `model`, `language`, `tone`, `userSide`;
/// * the audience level, the classifier version, the endpoint and the token
///   limit setting (a different server or limit can give a different answer);
/// * a hash of the complete messages that are sent, which carry the engine
///   lines, evals, flags and opening: so a re-analysis at another depth, a
///   changed classification or a template edit can never serve an old text.
///
/// The API key is not an input.
abstract final class CacheKey {
  static String of(PromptBundle bundle, LlmConfig config, {required int classifierVersion}) {
    final endpoint = BaseUrlPolicy.check(config.baseUrl).normalized ?? config.baseUrl.trim().toLowerCase();
    final messagesHash = sha256.convert(utf8.encode(jsonEncode([for (final m in bundle.messages) m.toJson()]))).toString();
    final preimage = jsonEncode([
      'glyph-llm-cache',
      PromptBuilder.version,
      bundle.kind.name,
      bundle.fenBefore,
      bundle.moveUci,
      bundle.label,
      config.model,
      bundle.prefs.language,
      bundle.prefs.tone.name,
      bundle.prefs.audience.name,
      bundle.userSide,
      classifierVersion,
      endpoint,
      config.tokenLimitMode.parameter,
      config.tokenLimitMode == TokenLimitMode.none ? 0 : config.tokenLimit,
      messagesHash,
    ]);
    return sha256.convert(utf8.encode(preimage)).toString();
  }
}
