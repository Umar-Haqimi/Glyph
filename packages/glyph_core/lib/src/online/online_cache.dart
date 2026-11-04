/// A stored response body with the `ETag` it came with.
class CachedResponse {
  const CachedResponse(this.etag, this.body);

  final String etag;
  final String body;
}

/// Where the chess.com client keeps `ETag`s (and the data they stand for) so
/// that a repeat request can send `If-None-Match` and reuse the stored body on
/// a 304. Implemented over SQLite in the app. Failures of a cache never break
/// a fetch: the client treats an exception as a miss.
abstract interface class OnlineCache {
  Future<CachedResponse?> get(String key);

  Future<void> put(String key, CachedResponse response);
}

class InMemoryOnlineCache implements OnlineCache {
  final Map<String, CachedResponse> entries = {};

  @override
  Future<CachedResponse?> get(String key) async => entries[key];

  @override
  Future<void> put(String key, CachedResponse response) async => entries[key] = response;
}
