import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// The HTTP client of one LLM request: a `dart:io` client with the 15 s
/// connection timeout of SPEC 6 (the `http` interface has no such setting,
/// the other two timeouts live in `LlmClient`). The only network access the
/// app makes besides the online game import (M7); no user agent, no cookies,
/// no proxy settings beyond the system's.
http.Client createLlmHttpClient() => IOClient(HttpClient()..connectionTimeout = Limits.connectTimeout);
