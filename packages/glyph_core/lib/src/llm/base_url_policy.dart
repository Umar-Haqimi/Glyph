/// Why a base URL was refused (SPEC section 6, "Network policy").
enum BaseUrlProblem {
  /// Nothing (or only blanks) was entered.
  empty,

  /// Not a parseable absolute URL.
  malformed,

  /// A scheme other than `https` / `http` (`ftp://`, `file://`, `javascript:` ...).
  unsupportedScheme,

  /// `user:pass@host`: credentials never belong in a URL (they would end up in
  /// logs, history and error messages).
  credentialsInUrl,

  /// A `?query` or `#fragment`: the client appends `/chat/completions` itself.
  queryOrFragment,

  /// `https:///v1`: no host.
  noHost,

  /// `http://` to a host that is not local or private. Plain http is only
  /// allowed for localhost, private ranges, Tailscale/CGNAT and `.local` /
  /// `.lan` names.
  cleartextNotAllowed,
}

/// Soft problems: the URL works as far as the policy is concerned.
enum BaseUrlWarning {
  /// No `/v1`-style path segment. Most OpenAI-compatible servers (OpenAI,
  /// OpenRouter `/api/v1`, Ollama, LM Studio, llama.cpp) serve under `/v1`.
  missingVersionPath,
}

/// The outcome of [BaseUrlPolicy.check].
class BaseUrlResult {
  const BaseUrlResult._({this.uri, this.problem, this.warnings = const []});

  /// The normalised URL (lower-case scheme and host, no trailing slash, no
  /// query, no fragment) when [ok].
  final Uri? uri;
  final BaseUrlProblem? problem;
  final List<BaseUrlWarning> warnings;

  bool get ok => uri != null;

  /// [uri] as text, without a trailing slash.
  String? get normalized => uri?.toString();

  @override
  String toString() => ok ? 'BaseUrlResult($uri)' : 'BaseUrlResult(${problem?.name})';
}

/// The gate in front of every request to the user's LLM endpoint (SPEC 6,
/// trap 14).
///
/// * `https://` is accepted for any host.
/// * `http://` only when [isLocalHost]: `localhost`, `127.0.0.0/8`,
///   `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10`
///   (Tailscale / CGNAT), `[::1]`, and names ending in `.local` or `.lan`.
/// * Every other scheme, credentials in the URL, a query string or a
///   fragment are refused.
///
/// The Android network security config permits cleartext globally (it cannot
/// list "private ranges"), so this class is the real gate; the client calls
/// it before it opens a socket.
abstract final class BaseUrlPolicy {
  /// Validates and normalises [input].
  static BaseUrlResult check(String input) {
    final text = input.trim();
    if (text.isEmpty) return const BaseUrlResult._(problem: BaseUrlProblem.empty);
    if (text.contains(RegExp(r'[\s\u0000-\u001f\u007f]'))) {
      return const BaseUrlResult._(problem: BaseUrlProblem.malformed);
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(text);
    } on FormatException {
      return const BaseUrlResult._(problem: BaseUrlProblem.malformed);
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme.isEmpty) return const BaseUrlResult._(problem: BaseUrlProblem.malformed);
    if (scheme != 'https' && scheme != 'http') {
      return const BaseUrlResult._(problem: BaseUrlProblem.unsupportedScheme);
    }
    // `https:example.com` and friends: require the `//` authority form.
    if (!text.substring(scheme.length).startsWith('://')) {
      return const BaseUrlResult._(problem: BaseUrlProblem.malformed);
    }
    // Look at the raw authority: Uri.userInfo hides `@host` with an empty user.
    final rest = text.substring(scheme.length + 3);
    final authority = rest.split(RegExp(r'[/?#]')).first;
    if (authority.contains('@') || parsed.userInfo.isNotEmpty) {
      return const BaseUrlResult._(problem: BaseUrlProblem.credentialsInUrl);
    }
    if (parsed.host.isEmpty) return const BaseUrlResult._(problem: BaseUrlProblem.noHost);
    if (parsed.hasQuery || parsed.hasFragment || text.contains('?') || text.contains('#')) {
      return const BaseUrlResult._(problem: BaseUrlProblem.queryOrFragment);
    }
    if (parsed.hasPort && (parsed.port <= 0 || parsed.port > 65535)) {
      return const BaseUrlResult._(problem: BaseUrlProblem.malformed);
    }
    final host = parsed.host.toLowerCase();
    if (scheme == 'http' && !isLocalHost(host)) {
      return const BaseUrlResult._(problem: BaseUrlProblem.cleartextNotAllowed);
    }
    final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
    final path = segments.isEmpty ? '' : '/${segments.join('/')}';
    final normalized = Uri(
      scheme: scheme,
      host: host,
      port: parsed.hasPort ? parsed.port : null,
      path: path,
    );
    final versioned = segments.any((s) => RegExp(r'^v\d', caseSensitive: false).hasMatch(s));
    return BaseUrlResult._(
      uri: normalized,
      warnings: versioned ? const [] : const [BaseUrlWarning.missingVersionPath],
    );
  }

  /// The chat completions endpoint for an accepted base URL.
  static Uri chatCompletions(Uri base) => base.replace(path: '${base.path}/chat/completions');

  /// True when plain `http://` is acceptable for [host] (and an API key is
  /// optional there): loopback, private ranges, CGNAT, `.local` / `.lan`.
  static bool isLocalHost(String host) {
    var h = host.toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    if (h.isEmpty) return false;
    if (h == 'localhost' || h == '::1' || h == '[::1]') return true;
    if (h.endsWith('.local') || h.endsWith('.lan')) return h.length > 4 && h != '.local' && h != '.lan';
    final ip = _ipv4(h);
    if (ip == null) return false;
    final [a, b, _, _] = ip;
    if (a == 127 || a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    return false;
  }

  /// Strict dotted-quad parse. Leading zeros are refused (`010.0.0.1` is octal
  /// to some resolvers), as are short forms (`127.1`) and numbers (`2130706433`):
  /// those are treated as ordinary host names, which http does not allow.
  static List<int>? _ipv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final out = <int>[];
    for (final p in parts) {
      if (!RegExp(r'^(0|[1-9]\d{0,2})$').hasMatch(p)) return null;
      final n = int.parse(p);
      if (n > 255) return null;
      out.add(n);
    }
    return out;
  }
}
