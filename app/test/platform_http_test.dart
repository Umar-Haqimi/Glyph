import 'package:flutter_test/flutter_test.dart';
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
}
