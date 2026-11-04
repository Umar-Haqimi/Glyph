import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app_info.dart';
import 'package:glyph/platform/llm_http.dart';
import 'package:glyph/platform/online_http.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:http/io_client.dart';

/// SPEC 6: connect timeout 15 s. The `http` interface has no such setting, so
/// the app's two client factories must set it on the `dart:io` client they build
/// (the first-byte and total limits live in the core clients, see
/// packages/glyph_core/test/limits_caps_test.dart).
void main() {
  test('both HTTP client factories apply Limits.connectTimeout (15 s)', () {
    expect(Limits.connectTimeout, const Duration(seconds: 15));
    expect(buildLlmHttpClient().connectionTimeout, Limits.connectTimeout);
    expect(buildOnlineHttpClient().connectionTimeout, Limits.connectTimeout);
    expect(createLlmHttpClient(), isA<IOClient>());
    expect(createOnlineHttpClient(), isA<IOClient>());
  });

  test('LLM requests carry the generic User-Agent "Glyph/<version>", not dart:io\'s "Dart/<sdk> (dart:io)" (PRIVACY.md section 2)', () async {
    expect(llmUserAgent, 'Glyph/$appVersion');
    expect(buildLlmHttpClient().userAgent, llmUserAgent);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <String?>[];
    final cookies = <String?>[];
    server.listen((request) {
      seen.add(request.headers.value('user-agent'));
      cookies.add(request.headers.value('cookie'));
      request.response
        ..write('ok')
        ..close();
    });
    final client = createLlmHttpClient();
    addTearDown(client.close);
    await HttpOverrides.runWithHttpOverrides(() async {
      final response = await createLlmHttpClient().get(Uri.parse('http://127.0.0.1:${server.port}/chat/completions'));
      expect(response.statusCode, 200);
    }, _RealHttpOverrides());
    expect(seen, ['Glyph/$appVersion']);
    expect(cookies, [null]);
  });
}

/// flutter_test replaces `HttpClient` with a stub that answers 400; this test
/// needs the real one to see what goes over a socket.
class _RealHttpOverrides extends HttpOverrides {}
