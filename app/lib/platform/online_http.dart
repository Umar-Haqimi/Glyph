import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../app_info.dart';

/// The HTTP client of one lichess / chess.com request: a `dart:io` client with
/// the 15 s connection timeout of SPEC 6 (first byte, idle and total limits
/// live in the clients). Together with `llm_http.dart` this is where the app
/// opens network connections (the hygiene test lists both).
http.Client createOnlineHttpClient() => IOClient(HttpClient()..connectionTimeout = Limits.connectTimeout);

/// Where chess.com `ETag`s are kept. `main()` provides the SQLite table; the
/// default (tests) is a map.
final onlineCacheProvider = Provider<OnlineCache>((ref) => InMemoryOnlineCache());

final lichessClientProvider = Provider<OnlineGamesClient>(
  (ref) => LichessClient(httpClient: createOnlineHttpClient, userAgent: onlineUserAgent),
);

final chessComClientProvider = Provider<OnlineGamesClient>(
  (ref) => ChessComClient(
    httpClient: createOnlineHttpClient,
    userAgent: onlineUserAgent,
    cache: ref.watch(onlineCacheProvider),
  ),
);
