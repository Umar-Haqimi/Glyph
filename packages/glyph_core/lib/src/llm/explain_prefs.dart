/// Tone of an explanation / summary (SPEC F14).
enum ExplainTone {
  casual,
  coach;

  static ExplainTone fromName(String? name) => values.where((t) => t.name == name).firstOrNull ?? casual;
}

/// Audience level (SPEC F14).
enum ExplainAudience {
  beginner,
  club,
  advanced;

  static ExplainAudience fromName(String? name) => values.where((t) => t.name == name).firstOrNull ?? club;
}

/// The explanation settings that shape a prompt (SPEC F14).
class ExplainPrefs {
  const ExplainPrefs({this.language = 'English', this.tone = ExplainTone.casual, this.audience = ExplainAudience.club});

  /// The language name written into the prompt, already resolved (the app
  /// language's English name, or the user's free-text override).
  final String language;
  final ExplainTone tone;
  final ExplainAudience audience;

  @override
  bool operator ==(Object other) =>
      other is ExplainPrefs && other.language == language && other.tone == tone && other.audience == audience;

  @override
  int get hashCode => Object.hash(language, tone, audience);
}
