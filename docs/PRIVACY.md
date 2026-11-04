# PRIVACY — what Glyph stores and what it sends (SPEC section 6, F20)

Last reviewed for v0.1.0 (M8). Glyph has **no account, no analytics, no crash reporting, no advertising and no server of its own**. Games, analyses and settings stay on your phone. The app contacts the network only when you ask it to, and only these three kinds of host:

| Host | When | What is sent |
|---|---|---|
| `lichess.org` | You tap Fetch in *Import > From lichess* | your lichess username (in the URL path) and the fixed request options listed below |
| `api.chess.com` | You tap Fetch in *Import > From chess.com* | your chess.com username (lower-cased, in the URL path) |
| the LLM server **you** configure (OpenAI, OpenRouter, Ollama, LM Studio, or your own) | You tap Explain, Summarize game, or Test connection; or an analysis finishes while *Summarize automatically* is on and a model is set up | engine facts about one move or one game (below), your model name, and your API key |

Nothing else is ever sent. The release APK requests exactly one permission, `android.permission.INTERNET` (plus the signature-level `my.umarh.glyph.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` that AndroidX adds for itself, which only Glyph can hold); `tool/check_permissions.sh` verifies this on every release build. It requests no storage, location, camera, microphone, contacts or network-state permission.

## 1. Requests to lichess.org and chess.com

- **lichess.org**: `GET https://lichess.org/api/games/user/{username}?max=30&pgnInJson=true&clocks=true&evals=true&opening=true&sort=dateDesc&perfType=...` with `Accept: application/x-ndjson`. The username is the one you typed (or the one saved in *Settings > Accounts*, which only prefills the field).
- **chess.com**: `GET https://api.chess.com/pub/player/{username}/games/archives`, then `GET .../games/{YYYY}/{MM}` for the newest months, one request at a time. When Glyph has fetched a month before it sends `If-None-Match` with the `ETag` the server gave it; that makes repeat fetches quick.
- Both: HTTPS only (hard-coded hosts), the header `User-Agent: Glyph/<version> (+https://github.com/Umar-Haqimi/Glyph)` (an app name and the project's address: no e-mail address and nothing about you), **no cookies, no credentials, no API token**. The sites see what any HTTPS request shows: your IP address and the time.
- No redirect is followed. A response larger than 16 MB, a line longer than 1 MB, or more than 50 games per fetch is refused (`Limits`).
- The games that arrive are public game records. Glyph saves a game only when you select it and tap Import. For chess.com it also keeps, in the local `http_cache` table, a trimmed copy of each fetched month (so a `304 Not Modified` can be answered from disk); *Settings > Data > Clear online cache* removes it.

## 2. Requests to your LLM server

Every request goes to **the base URL you entered** (`https://` anywhere; `http://` only for `localhost`, private network ranges, Tailscale `100.64.0.0/10`, and `.local` / `.lan` names, enforced before any connection). It is `POST {baseUrl}/chat/completions` with:

- **Header** `Authorization: Bearer <your API key>`, only if a key is stored for that exact address (see section 4). A local server without a key gets no header.
- **Body** `{"model": ..., "messages": [system, user], "stream": true}`, plus `max_tokens` or `max_completion_tokens` only if you chose one in *Settings*. Glyph never sends `temperature`.
- **The system message**: fixed instructions (in the app, versioned).
- **The user message for "Explain"**, a JSON object of engine facts about one move: the move in SAN and its number, which side moved and whether it was your move ("you"), the label (Blunder, Brilliant, ...), the position before the move as a FEN, win chances and evaluations before and after (from the mover's point of view), the engine's best line and second-best line in SAN with their evaluations, the line that refutes the move, material balance, pieces left hanging, a few flags (sacrifice, only move, missed mate, punished an error), the opening name, the game phase (opening / middlegame / endgame), and your chosen audience level, tone and explanation language.
- **The user message for the game summary**: the result and how the game ended (derived from the final position, not from any header), whether you won, the opening name, your side, both accuracy percentages, how many moves of each label each side played, up to 8 key moments (move number, side, SAN, label, win chance before and after, the engine's best move in SAN), White's win chance every 5 plies, and your audience level, tone and language.
- **Test connection** sends one fixed sentence ("Reply with the single word OK.") and the model name.

**Never sent to the LLM:** player names, usernames, ratings, titles, the lichess or chess.com site or game URL, event or round names, dates, time controls, clocks, PGN comments, the PGN itself, or anything about your device. Tests build prompts from a game full of identifying headers and fail if any of it appears (`packages/glyph_core/test/llm/prompt_builder_test.dart`, snapshot files in `test/vectors/prompts/`). "View prompt" in the Explain sheet shows the exact messages (without the key).

What the server does with these facts is governed by that provider's own terms and privacy policy. If you use OpenAI or OpenRouter, they receive the facts above and your API key. If you use Ollama or LM Studio on your own computer, the facts stay on your network.

## 3. What is stored on the phone

All of it is in the app's private storage and is excluded from Android backups (`android:allowBackup="false"` and empty `dataExtractionRules`), so nothing is copied to the cloud or to a new phone.

| What | Where | Notes |
|---|---|---|
| Games (the PGN as imported, players, result, date, source, your side), analyses (engine lines, labels, accuracy) | SQLite database `glyph.db` | deleted by *Delete all data* or by deleting a game |
| Saved explanations and summaries | table `llm_cache` | the text the model returned, keyed by a hash; *Clear saved explanations* removes them |
| chess.com `ETag` copies | table `http_cache` | public game data; *Clear online cache* removes it |
| Settings (engine, appearance, usernames you saved, model name, language, tone, ...) | table `settings` | never a secret |
| API keys | Android Keystore-backed secure storage (`flutter_secure_storage`, default options) | one slot per provider preset; never in SQLite, settings, logs, the clipboard, an exported PGN or "View prompt"; shown only as `••••abcd`; *Remove key* or *Delete all data* erases it |
| The last exported PGN | `cache/shared_pgn/` | one file, replaced by the next export, removed with the app's cache |
| Anything you share *into* Glyph (a PGN text or file from another app) | memory only | read up to 2 MB, parsed, and kept only if you tap Save |

The Explain and summary text you read is rendered as plain text; no web view, link or image from a model is ever loaded.

## 4. How the API key is protected

- It is read from secure storage when a request is built and not kept in app state afterwards. Dart strings cannot be wiped from memory; keeping the lifetime short is the mitigation.
- It is **bound to the address it was saved for** (scheme, host and port). If you change the base URL, the key is not sent to the new address until you save it again there. Over plain `http://` it is sent only after you switch on *Send the key over unencrypted http* for that address.
- Error messages from a provider have any copy of the key removed. A hygiene test fails if the word `Authorization` appears anywhere in the app except the one line in the core client that sets the header.
- No screen capture block (`FLAG_SECURE`) is set: nothing sensitive is displayed (the key is masked).

## 5. Logging and diagnostics

Glyph logs nothing below warning level and only through one wrapper (`AppLog`). A log line is a fixed sentence plus the **type** of the error ("Opening the database failed (StateError)"): never a message, a PGN, a name, a URL, a prompt or a key. There is no crash reporter and no telemetry; a crash leaves nothing but Android's own report on the device. Tests scan the sources for `print`, `debugPrint`, `developer.log` and Android `Log` calls, and for analytics or crash-reporting packages (`tool/check_banned_deps.sh` runs in CI and fails if `pubspec.lock` or a Gradle file contains Firebase, Play Services, Sentry, Crashlytics, ad or analytics SDKs).

## 6. Your controls

- *Settings > Data > Clear saved explanations*, *Clear online cache*, *Delete all data* (games, analyses, explanations, caches, every setting and every API key; asks first).
- *Settings > Explanations > LLM connection > Remove key*.
- Swipe a game away in the library, or *Delete game* in the board menu.
- Uninstalling the app removes everything it stored.
- Airplane mode: importing pasted PGN, analysing and reviewing a game all work offline; only Explain, summaries and online import need a connection.

## 7. Contact and changes

Questions and reports go to the project's issue tracker, <https://github.com/Umar-Haqimi/Glyph/issues>. A change to what Glyph sends is a change to this file and to the prompt tests in the same commit.
