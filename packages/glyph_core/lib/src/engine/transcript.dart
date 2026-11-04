/// A recorded engine conversation: for each `position ...` + `go ...` command
/// pair, the raw engine output up to and including `bestmove`.
///
/// Text format (`packages/glyph_core/test/vectors/uci_transcripts/*.txt`):
///
/// ```
/// # free-form header lines (engine, settings, game)
/// > position startpos moves e2e4
/// > go depth 16
/// info depth 1 seldepth 1 multipv 1 score cp 33 ...
/// bestmove e7e5 ponder g1f3
///
/// > position startpos moves e2e4 e7e5
/// ...
/// ```
///
/// `>` lines are commands we sent, every other non-`#`, non-blank line is raw
/// engine output (verbatim). A block ends at the next `>` line after output.
class Transcript {
  Transcript({List<String> header = const [], Map<String, List<String>>? entries})
      : header = List.of(header),
        entries = entries ?? {};

  /// Header comment lines without the leading `# `.
  final List<String> header;

  /// key (see [keyFor]) -> raw output lines, `bestmove` last.
  final Map<String, List<String>> entries;

  /// The lookup key for a search: the exact `position ...` and `go ...`
  /// commands.
  static String keyFor(String positionCommand, String goCommand) => '$positionCommand\n$goCommand';

  void add(String positionCommand, String goCommand, List<String> output) {
    entries[keyFor(positionCommand, goCommand)] = List.of(output);
  }

  static Transcript parse(String text) {
    final header = <String>[];
    final entries = <String, List<String>>{};
    String? position, go;
    List<String>? output;

    void flush() {
      if (position != null && go != null && output != null && output!.isNotEmpty) {
        entries[keyFor(position!, go!)] = output!;
      }
      position = go = null;
      output = null;
    }

    for (final raw in text.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        header.add(line.length > 2 ? line.substring(2) : '');
      } else if (line.startsWith('> ')) {
        final cmd = line.substring(2);
        if (cmd.startsWith('position')) {
          flush();
          position = cmd;
        } else if (cmd.startsWith('go')) {
          go = cmd;
          output = [];
        }
      } else {
        output?.add(line);
      }
    }
    flush();
    return Transcript(header: header, entries: entries);
  }

  String serialize() {
    final b = StringBuffer();
    for (final h in header) {
      b.writeln('# $h');
    }
    for (final e in entries.entries) {
      final parts = e.key.split('\n');
      b.writeln();
      b.writeln('> ${parts[0]}');
      b.writeln('> ${parts[1]}');
      for (final l in e.value) {
        b.writeln(l);
      }
    }
    return b.toString();
  }

  /// Merges [other] into this transcript (later entries win).
  void addAll(Transcript other) => entries.addAll(other.entries);
}
