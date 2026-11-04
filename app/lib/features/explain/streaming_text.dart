import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:material_ui/material_ui.dart';

/// The answer text with screen-reader support for a growing text.
///
/// A plain `liveRegion` on the whole text would make TalkBack read the
/// *entire* text again after every token. Instead, while text is streaming,
/// the node's spoken label is only the **newly completed sentences** (a live
/// region announces each change of its label), so the reader hears the
/// explanation sentence by sentence and never twice. When streaming ends the
/// unspoken tail is announced once and the node then reads the whole text
/// (not as a live region, so nothing is repeated). With [announceOnShow], a
/// text that is already complete when the widget appears (a saved
/// explanation) is announced in full.
class StreamingText extends StatefulWidget {
  const StreamingText({
    super.key,
    required this.text,
    required this.streaming,
    this.style,
    this.announceOnShow = false,
  });

  final String text;
  final bool streaming;
  final TextStyle? style;
  final bool announceOnShow;

  /// The index up to which [text] is made of whole sentences (`. ` `! ` `? `
  /// or a line break), or 0.
  static int sentenceEnd(String text) {
    var end = 0;
    for (final m in RegExp('[.!?…]["\'”)\\]]*\\s|\\n').allMatches(text)) {
      end = m.end;
    }
    return end;
  }

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText> {
  int _spoken = 0;
  String _live = '';

  @override
  void initState() {
    super.initState();
    if (widget.streaming) {
      _advance();
    } else if (widget.announceOnShow && widget.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce(widget.text));
    }
  }

  @override
  void didUpdateWidget(StreamingText old) {
    super.didUpdateWidget(old);
    if (!widget.text.startsWith(old.text.substring(0, _spoken.clamp(0, old.text.length)))) {
      _spoken = 0; // a different text (Regenerate): start over
      _live = '';
    }
    if (widget.streaming) {
      _advance();
    } else if (old.streaming) {
      final tail = widget.text.substring(_spoken.clamp(0, widget.text.length)).trim();
      _spoken = widget.text.length;
      _live = '';
      if (tail.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _announce(tail));
    }
  }

  void _advance() {
    final end = StreamingText.sentenceEnd(widget.text);
    if (end > _spoken) {
      _live = widget.text.substring(_spoken, end).trim();
      _spoken = end;
    }
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(View.of(context), message, Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text, style: widget.style);
    return Semantics(
      key: const Key('streaming-text-node'),
      label: widget.streaming ? _live : widget.text,
      liveRegion: widget.streaming,
      excludeSemantics: true,
      child: text,
    );
  }
}
