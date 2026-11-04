import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The share sheet could not be opened.
class PgnShareException implements Exception {
  const PgnShareException();

  @override
  String toString() => 'PgnShareException';
}

/// Hands a PGN to the Android share sheet (SPEC F18). An interface so tests can
/// fake the platform.
abstract interface class PgnShareService {
  /// [fileName] is already sanitised ([exportFileName]); [title] is the
  /// chooser's heading. Throws [PgnShareException].
  Future<void> share({required String pgn, required String fileName, required String title});
}

/// The `my.umarh.glyph/export` MethodChannel implemented by `MainActivity.kt`:
/// the PGN is written to the app cache, exposed through a FileProvider URI
/// with a read grant, and offered to the share sheet. No storage permission.
class ChannelPgnShareService implements PgnShareService {
  const ChannelPgnShareService({this.channel = const MethodChannel(channelName)});

  static const channelName = 'my.umarh.glyph/export';

  final MethodChannel channel;

  @override
  Future<void> share({required String pgn, required String fileName, required String title}) async {
    try {
      await channel.invokeMethod<void>('sharePgn', {'text': pgn, 'fileName': fileName, 'title': title});
    } on MissingPluginException {
      throw const PgnShareException();
    } on PlatformException {
      throw const PgnShareException();
    }
  }
}

final pgnShareServiceProvider = Provider<PgnShareService>((ref) => const ChannelPgnShareService());
