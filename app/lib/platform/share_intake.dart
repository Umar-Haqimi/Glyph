import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

/// What Android handed to the app through Share or "Open with" (SPEC F2).
sealed class SharedContent {
  const SharedContent();
}

/// Shared text: a PGN, or anything else a share sheet can carry (a link).
class SharedText extends SharedContent {
  const SharedText(this.text);

  final String text;
}

/// A shared or opened file, at most [Limits.maxPgnBytes] bytes.
class SharedFile extends SharedContent {
  const SharedFile(this.bytes);

  final Uint8List bytes;
}

/// The text or file is over the 2 MB cap (it was not kept).
class SharedTooLarge extends SharedContent {
  const SharedTooLarge();
}

/// The intent could not be read (no read grant, a broken stream, junk extras).
class SharedUnreadable extends SharedContent {
  const SharedUnreadable();
}

/// The Dart side of the share / open-with intake. An interface so tests can
/// fake the platform.
abstract interface class ShareIntakeService {
  /// Everything that arrives after [start]. Broadcast; events with no
  /// listener are dropped, so listen first.
  Stream<SharedContent> get shared;

  /// Tells the platform that the app listens: what arrived earlier (the
  /// launching intent) is delivered now. Safe to call again.
  Future<void> start();
}

/// The `my.umarh.glyph/intake` MethodChannel implemented by `MainActivity.kt`.
/// The native side reads at most 2 MB, never writes to disk, and sends a map
/// `{kind: text|file|tooLarge|error, ...}`; [decode] checks it again, because a
/// channel is an input like any other.
class ChannelShareIntakeService implements ShareIntakeService {
  ChannelShareIntakeService({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'my.umarh.glyph/intake';

  final MethodChannel _channel;
  final _controller = StreamController<SharedContent>.broadcast();

  @override
  Stream<SharedContent> get shared => _controller.stream;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'shared') throw MissingPluginException();
    _controller.add(decode(call.arguments));
    return null;
  }

  @override
  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Not Android (or a test without a native side): nothing will arrive.
    } on PlatformException {
      // The native side failed; sharing into the app just does nothing.
    }
  }

  /// Turns a message from the platform into a [SharedContent]; never throws.
  static SharedContent decode(Object? message) {
    if (message is! Map) return const SharedUnreadable();
    switch (message['kind']) {
      case 'text':
        final text = message['text'];
        if (text is! String || text.trim().isEmpty) return const SharedUnreadable();
        if (utf8.encode(text).length > Limits.maxPgnBytes) return const SharedTooLarge();
        return SharedText(text);
      case 'file':
        final bytes = message['bytes'];
        if (bytes is! Uint8List) return const SharedUnreadable();
        if (bytes.length > Limits.maxPgnBytes) return const SharedTooLarge();
        return SharedFile(bytes);
      case 'tooLarge':
        return const SharedTooLarge();
      default:
        return const SharedUnreadable();
    }
  }
}

final shareIntakeServiceProvider = Provider<ShareIntakeService>((ref) => ChannelShareIntakeService());
