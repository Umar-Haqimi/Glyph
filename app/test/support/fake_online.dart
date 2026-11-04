import 'dart:async';

import 'package:glyph_core/glyph_core.dart';

/// A scripted game source for widget tests. [script] receives the cancel
/// token and an emitter and returns the outcome; it can wait on completers to
/// show intermediate states.
class FakeOnlineClient implements OnlineGamesClient {
  FakeOnlineClient(this.script);

  final Future<OnlineFetchOutcome> Function(String username, OnlineCancelToken token, void Function(OnlineEvent) emit) script;
  final usernames = <String>[];
  final tokens = <OnlineCancelToken>[];

  /// Returns [games] one by one, then finishes.
  factory FakeOnlineClient.games(List<OnlineGame> games, {int skipped = 0, OnlineFetchError? error}) =>
      FakeOnlineClient((username, token, emit) async {
        for (var i = 0; i < games.length; i++) {
          emit(OnlineGameReceived(games[i], i + 1));
        }
        return OnlineFetchOutcome(games: games, skipped: skipped, error: error);
      });

  factory FakeOnlineClient.failing(OnlineFetchError error) =>
      FakeOnlineClient((username, token, emit) async => OnlineFetchOutcome(error: error));

  @override
  Future<OnlineFetchOutcome> fetchGames(String username, {int max = 30, OnlineCancelToken? cancel, void Function(OnlineEvent event)? onEvent}) {
    usernames.add(username);
    final token = cancel ?? OnlineCancelToken();
    tokens.add(token);
    return script(username, token, onEvent ?? (_) {});
  }
}

const _moves = '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7';

/// A lichess game with a PGN that imports.
OnlineGame lichessOnline(
  String id, {
  String white = 'alice',
  String black = 'bob',
  OnlineSpeed speed = OnlineSpeed.blitz,
  String result = '1-0',
  int playedAt = 1700000000000,
  String? pgn,
}) =>
    OnlineGame(
      source: OnlineSource.lichess,
      sourceId: id,
      pgn: pgn ??
          '[Event "Rated ${speed.name} game"]\n[Site "https://lichess.org/$id"]\n[Date "2023.11.14"]\n[White "$white"]\n[Black "$black"]\n[Result "$result"]\n[WhiteElo "1500"]\n[BlackElo "1480"]\n\n$_moves $result\n',
      white: white,
      black: black,
      whiteRating: 1500,
      blackRating: 1480,
      speed: speed,
      timeControl: '180+2',
      result: result,
      playedAtMs: playedAt,
    );

OnlineGame chessComOnline(
  String id, {
  String white = 'Alice',
  String black = 'Bob',
  OnlineSpeed speed = OnlineSpeed.blitz,
  int playedAt = 1700000000000,
}) =>
    OnlineGame(
      source: OnlineSource.chesscom,
      sourceId: 'https://www.chess.com/game/live/$id',
      pgn: '[Event "Live Chess"]\n[Site "Chess.com"]\n[Date "2023.11.14"]\n[White "$white"]\n[Black "$black"]\n[Result "0-1"]\n\n$_moves 0-1\n',
      white: white,
      black: black,
      whiteRating: 1200,
      blackRating: 1250,
      speed: speed,
      timeControl: '600',
      result: '0-1',
      playedAtMs: playedAt,
    );
