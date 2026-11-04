/// Facts about the app that are sent to the outside world or shown to the user.
/// `test/hygiene_test.dart` checks [appVersion] against `pubspec.yaml`.
const String appVersion = '0.1.0';

/// The project's source repository.
const String projectUrl = 'https://github.com/Umar-Haqimi/Glyph';

/// The `User-Agent` of every request to lichess and chess.com (SPEC 2.1,
/// chess.com asks for a recognisable one): the app name, its version and the
/// repository, nothing about the user and no e-mail address.
const String onlineUserAgent = 'Glyph/$appVersion (+$projectUrl)';
