import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

void main() {
  group('Limits (SPEC section 6)', () {
    test('PGN input cap is 2 MB', () {
      expect(Limits.maxPgnBytes, 2 * 1024 * 1024);
    });

    test('game, ply and comment caps', () {
      expect(Limits.maxGamesPerFile, 500);
      expect(Limits.maxPliesPerGame, 1000);
      expect(Limits.maxCommentBytes, 4096);
    });

    test('online fetch: 30 by default, never more than 50; response, retry and wait caps', () {
      expect(Limits.defaultOnlineGames, 30);
      expect(Limits.maxOnlineResponseBytes, 16 * 1024 * 1024);
      expect(Limits.maxChessComArchiveRequests, 36);
      expect(Limits.rateLimitWait, const Duration(seconds: 60));
      expect(Limits.maxRateLimitWait, const Duration(minutes: 5));
      expect(Limits.maxRateLimitRetries, 2);
    });

    test('online fetch caps', () {
      expect(Limits.maxOnlineGames, 50);
      expect(Limits.maxNdjsonLineBytes, 1024 * 1024);
    });

    test('LLM stream cap is 32 KB', () {
      expect(Limits.maxLlmStreamBytes, 32 * 1024);
    });

    test('total LLM stream cap is 1 MB, above the 32 KB text cap', () {
      expect(Limits.maxLlmTotalStreamBytes, 1024 * 1024);
      expect(Limits.maxLlmTotalStreamBytes, greaterThan(Limits.maxLlmStreamBytes));
    });

    test('SSE event and error body caps', () {
      expect(Limits.maxSseEventBytes, 256 * 1024);
      expect(Limits.maxLlmErrorBodyBytes, 64 * 1024);
    });

    test('timeouts: connect 15 s, first byte 60 s, total 180 s', () {
      expect(Limits.connectTimeout, const Duration(seconds: 15));
      expect(Limits.firstByteTimeout, const Duration(seconds: 60));
      expect(Limits.totalTimeout, const Duration(seconds: 180));
      expect(Limits.connectTimeout < Limits.firstByteTimeout, isTrue);
      expect(Limits.firstByteTimeout < Limits.totalTimeout, isTrue);
    });
  });
}
