import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A request the fake site saw.
class Seen {
  Seen(this.method, this.uri, this.headers);

  final String method;
  final Uri uri;
  final Map<String, String?> headers;

  String get path => uri.path;
}

/// A local `dart:io` server standing in for lichess / chess.com. No test
/// touches the real network.
class FakeSite {
  FakeSite._(this.server);

  final HttpServer server;
  final requests = <Seen>[];
  Future<void> Function(HttpRequest request, Seen seen)? handler;
  final disconnects = <Completer<void>>[];

  static Future<FakeSite> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final site = FakeSite._(server);
    server.listen((req) async {
      final seen = Seen(req.method, req.uri, {
        for (final h in ['user-agent', 'accept', 'authorization', 'if-none-match', 'cookie']) h: req.headers.value(h),
      });
      site.requests.add(seen);
      try {
        await site.handler!(req, seen);
      } on Object {
        // the client went away
      }
    });
    return site;
  }

  Uri get baseUri => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> close() => server.close(force: true);
}

const userAgent = 'Glyph/0.1.0 (+https://github.com/Umar-Haqimi/Glyph)';

http.Client plainClient() => IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 5));

/// Sends [bytes] as an NDJSON body in chunks of [chunkSize], flushing between
/// chunks so the client really sees them split.
Future<void> sendChunked(HttpResponse response, List<int> bytes, int chunkSize, {String type = 'application/x-ndjson'}) async {
  response.bufferOutput = false;
  response.headers.contentType = ContentType.parse(type);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = i + chunkSize > bytes.length ? bytes.length : i + chunkSize;
    response.add(bytes.sublist(i, end));
    await response.flush();
    await Future<void>.delayed(Duration.zero);
  }
  await response.close();
}

Future<void> sendJson(HttpResponse response, Object body, {int status = 200, Map<String, String> headers = const {}}) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  headers.forEach(response.headers.set);
  response.write(jsonEncode(body));
  await response.close();
}

Future<void> sendStatus(HttpResponse response, int status, {Map<String, String> headers = const {}}) async {
  response.statusCode = status;
  headers.forEach(response.headers.set);
  await response.close();
}

/// A lichess export object (only the fields the client reads, plus a PGN).
Map<String, Object?> lichessGame(
  String id, {
  String white = 'alice',
  String black = 'bob',
  String variant = 'standard',
  String speed = 'blitz',
  String status = 'resign',
  String? winner = 'white',
  int createdAt = 1700000000000,
  String moves = 'e4 e5',
  bool omitPgn = false,
}) =>
    {
      'id': id,
      'rated': true,
      'variant': variant,
      'speed': speed,
      'perf': speed,
      'createdAt': createdAt,
      'status': status,
      'winner': ?winner,
      'players': {
        'white': {'user': {'name': white, 'id': white.toLowerCase()}, 'rating': 1500},
        'black': {'user': {'name': black, 'id': black.toLowerCase()}, 'rating': 1480},
      },
      'moves': moves,
      'clock': {'initial': 180, 'increment': 2, 'totalTime': 260},
      if (!omitPgn)
        'pgn': '[Event "Rated $speed game"]\n[Site "https://lichess.org/$id"]\n[White "$white"]\n[Black "$black"]\n[Result "1-0"]\n\n1. e4 e5 1-0\n',
    };

String ndjson(Iterable<Map<String, Object?>> games) => games.map((g) => '${jsonEncode(g)}\n').join();

/// A chess.com game object.
Map<String, Object?> chessComGame(
  String id, {
  String rules = 'chess',
  String timeClass = 'blitz',
  int endTime = 1790000000,
  String white = 'Alice',
  String black = 'Bob',
  String whiteResult = 'win',
  String blackResult = 'resigned',
  int pgnPadding = 0,
}) =>
    {
      'url': 'https://www.chess.com/game/live/$id',
      'pgn': '[Event "Live Chess"]\n[Site "Chess.com"]\n[White "$white"]\n[Black "$black"]\n[Result "1-0"]\n\n1. e4 {[%clk 0:03:00]} 1... e5 {[%clk 0:03:00]} 1-0\n${' ' * pgnPadding}',
      'time_control': '180',
      'end_time': endTime,
      'rated': true,
      'time_class': timeClass,
      'rules': rules,
      'white': {'rating': 1500, 'result': whiteResult, 'username': white},
      'black': {'rating': 1480, 'result': blackResult, 'username': black},
    };

String archiveUrl(String user, int y, int m) => 'https://api.chess.com/pub/player/$user/games/$y/${m.toString().padLeft(2, '0')}';

List<OnlineEvent> recordEvents(List<OnlineEvent> sink) => sink;
