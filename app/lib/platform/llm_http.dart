import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../app_info.dart';

/// The HTTP client of one LLM request: a `dart:io` client with the 15 s
/// connection timeout of SPEC 6 (the `http` interface has no such setting,
/// the other two timeouts live in `LlmClient`). The only network access the
/// app makes besides the online game import (M7). The `User-Agent` is the
/// generic [llmUserAgent] (`Glyph/<version>`), set explicitly because dart:io's
/// default would be `Dart/<sdk> (dart:io)`; no cookies are kept or sent, and no
/// proxy settings beyond the system's.
http.Client createLlmHttpClient() => IOClient(buildLlmHttpClient());

/// The `dart:io` client under [createLlmHttpClient] (a test reads its timeout).
@visibleForTesting
HttpClient buildLlmHttpClient() => HttpClient()
  ..connectionTimeout = Limits.connectTimeout
  ..userAgent = llmUserAgent;
