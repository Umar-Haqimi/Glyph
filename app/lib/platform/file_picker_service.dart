import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

/// A picked PGN file: its bytes, or [tooLarge] when it exceeds the 2 MB cap
/// (in which case it was not read into memory).
class PickedPgn {
  const PickedPgn.bytes(this.name, Uint8List this.bytes) : tooLarge = false;
  const PickedPgn.tooLarge(this.name)
      : bytes = null,
        tooLarge = true;

  final String name;
  final Uint8List? bytes;
  final bool tooLarge;
}

/// The system file picker (Storage Access Framework on Android, so no storage
/// permission). An interface so widget tests can fake it.
abstract interface class FilePickerService {
  /// Returns null when the user cancels.
  Future<PickedPgn?> pickPgn();
}

class SystemFilePickerService implements FilePickerService {
  const SystemFilePickerService();

  @override
  Future<PickedPgn?> pickPgn() async {
    // FileType.any: file managers often report .pgn as octet-stream/text, which
    // a mime-based filter would grey out.
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final known = file.lengthSync();
    if (known != null && known > Limits.maxPgnBytes) return PickedPgn.tooLarge(file.name);
    // Read at most maxPgnBytes + 1 so a huge file never fills memory.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      builder.add(chunk);
      if (builder.length > Limits.maxPgnBytes) return PickedPgn.tooLarge(file.name);
    }
    return PickedPgn.bytes(file.name, builder.takeBytes());
  }
}

final filePickerServiceProvider = Provider<FilePickerService>((ref) => const SystemFilePickerService());
