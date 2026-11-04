import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

void main() {
  BaseUrlProblem? problem(String s) => BaseUrlPolicy.check(s).problem;

  group('https is accepted anywhere', () {
    for (final url in [
      'https://api.openai.com/v1',
      'https://openrouter.ai/api/v1',
      'https://my-llm.example.org',
      'https://8.8.8.8/v1',
      'https://example.com:8443/v1',
      'HTTPS://API.OpenAI.com/v1',
    ]) {
      test(url, () => expect(BaseUrlPolicy.check(url).ok, isTrue));
    }
  });

  group('cleartext http only for local and private hosts', () {
    const allowed = [
      'http://localhost:11434/v1',
      'http://LOCALHOST/v1',
      'http://127.0.0.1:1234/v1',
      'http://127.255.255.254/v1',
      'http://10.0.0.5:11434/v1',
      'http://10.255.255.255/v1',
      'http://172.16.0.1/v1',
      'http://172.31.255.255/v1',
      'http://192.168.1.5:11434/v1',
      'http://100.64.0.1/v1',
      'http://100.127.255.255/v1',
      'http://[::1]:11434/v1',
      'http://mac-studio.local:1234/v1',
      'http://homelab.lan/v1',
      'http://nas.example.lan:8080/v1',
    ];
    for (final url in allowed) {
      test('allows $url', () => expect(BaseUrlPolicy.check(url).ok, isTrue, reason: url));
    }

    const blocked = [
      'http://api.openai.com/v1',
      'http://example.com/v1',
      'http://8.8.8.8/v1',
      'http://172.15.0.1/v1', // just below 172.16/12
      'http://172.32.0.1/v1', // just above
      'http://100.63.255.255/v1',
      'http://100.128.0.1/v1',
      'http://192.169.0.1/v1',
      'http://11.0.0.1/v1',
      'http://169.254.169.254/v1', // link-local / cloud metadata
      'http://192.168.1.5.evil.com/v1', // looks private, is a public name
      'http://localhost.evil.com/v1',
      'http://evil.local.com/v1',
      'http://local/v1',
      'http://lan/v1',
      'http://.lan/v1',
      'http://010.0.0.1/v1', // octal ambiguity
      'http://0x7f.0.0.1/v1',
      'http://2130706433/v1', // decimal form of 127.0.0.1
      'http://127.1/v1',
      'http://0.0.0.0/v1',
      'http://[2001:db8::1]/v1',
      'http://[::ffff:127.0.0.1]/v1',
    ];
    for (final url in blocked) {
      test('blocks $url', () => expect(problem(url), BaseUrlProblem.cleartextNotAllowed, reason: url));
    }
  });

  group('other refusals', () {
    final cases = <String, BaseUrlProblem>{
      '': BaseUrlProblem.empty,
      '   ': BaseUrlProblem.empty,
      'ftp://example.com/v1': BaseUrlProblem.unsupportedScheme,
      'file:///etc/passwd': BaseUrlProblem.unsupportedScheme,
      'javascript:alert(1)': BaseUrlProblem.unsupportedScheme,
      'ws://localhost/v1': BaseUrlProblem.unsupportedScheme,
      'localhost:11434/v1': BaseUrlProblem.unsupportedScheme, // parses as scheme "localhost"
      'api.openai.com/v1': BaseUrlProblem.malformed,
      'https:example.com': BaseUrlProblem.malformed,
      'https://user:pass@example.com/v1': BaseUrlProblem.credentialsInUrl,
      'https://sk-abc@example.com/v1': BaseUrlProblem.credentialsInUrl,
      'https://@example.com/v1': BaseUrlProblem.credentialsInUrl,
      'http://user@192.168.1.5/v1': BaseUrlProblem.credentialsInUrl,
      'https://example.com/v1?key=abc': BaseUrlProblem.queryOrFragment,
      'https://example.com/v1?': BaseUrlProblem.queryOrFragment,
      'https://example.com/v1#frag': BaseUrlProblem.queryOrFragment,
      'https:///v1': BaseUrlProblem.noHost,
      'https://exa mple.com/v1': BaseUrlProblem.malformed,
      'https://example.com:99999/v1': BaseUrlProblem.malformed,
    };
    cases.forEach((url, expected) {
      test(url.isEmpty ? '(empty)' : url.trim().isEmpty ? '(blank)' : url, () => expect(problem(url), expected, reason: url));
    });

    test('surrounding whitespace and a trailing newline are trimmed, not refused', () {
      expect(BaseUrlPolicy.check(' https://example.com/v1\n').normalized, 'https://example.com/v1');
    });

    test('control characters inside the URL are malformed', () {
      expect(problem('https://exa\u0000mple.com/v1'), BaseUrlProblem.malformed);
      expect(problem('https://example.com/v1\u007f'), BaseUrlProblem.malformed);
    });
  });

  group('normalisation', () {
    String? norm(String s) => BaseUrlPolicy.check(s).normalized;

    test('trims, lower-cases scheme and host, drops trailing slashes', () {
      expect(norm('  HTTPS://API.OpenAI.com/v1/  '), 'https://api.openai.com/v1');
      expect(norm('https://api.openai.com/v1///'), 'https://api.openai.com/v1');
      expect(norm('https://example.com/'), 'https://example.com');
      expect(norm('http://192.168.1.5:11434/v1/'), 'http://192.168.1.5:11434/v1');
    });

    test('keeps the path case and the port', () {
      expect(norm('https://host.example:8443/API/V1'), 'https://host.example:8443/API/V1');
    });

    test('the chat completions endpoint is appended once', () {
      final base = BaseUrlPolicy.check('https://openrouter.ai/api/v1/').uri!;
      expect(BaseUrlPolicy.chatCompletions(base).toString(), 'https://openrouter.ai/api/v1/chat/completions');
      final bare = BaseUrlPolicy.check('https://example.com').uri!;
      expect(BaseUrlPolicy.chatCompletions(bare).toString(), 'https://example.com/chat/completions');
    });

    test('warns when there is no /v1-style path segment', () {
      expect(BaseUrlPolicy.check('https://api.openai.com/v1').warnings, isEmpty);
      expect(BaseUrlPolicy.check('https://openrouter.ai/api/v1').warnings, isEmpty);
      expect(BaseUrlPolicy.check('https://generativelanguage.googleapis.com/v1beta/openai').warnings, isEmpty);
      expect(BaseUrlPolicy.check('http://192.168.1.5:11434').warnings, [BaseUrlWarning.missingVersionPath]);
      expect(BaseUrlPolicy.check('https://example.com/api').warnings, [BaseUrlWarning.missingVersionPath]);
    });

    test('a refused URL has no normalised form', () {
      expect(BaseUrlPolicy.check('http://example.com/v1').uri, isNull);
      expect(BaseUrlPolicy.check('http://example.com/v1').normalized, isNull);
    });
  });

  group('isLocalHost', () {
    test('decides key optionality helpers', () {
      expect(BaseUrlPolicy.isLocalHost('localhost'), isTrue);
      expect(BaseUrlPolicy.isLocalHost('localhost.'), isTrue);
      expect(BaseUrlPolicy.isLocalHost('192.168.0.9'), isTrue);
      expect(BaseUrlPolicy.isLocalHost('api.openai.com'), isFalse);
      expect(BaseUrlPolicy.isLocalHost(''), isFalse);
    });
  });
}
