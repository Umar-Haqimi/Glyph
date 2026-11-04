import 'package:material_ui/material_ui.dart';

/// A single-choice control: a [SegmentedButton] at normal text sizes and a
/// vertical list of options when the user's text scale is large. Segments
/// cannot wrap, so three labels at 2x text on a 360 dp phone would overflow.
class AdaptiveSegments<T> extends StatelessWidget {
  const AdaptiveSegments({
    super.key,
    this.controlKey,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.listThreshold = 1.3,
  });

  /// Key of the [SegmentedButton] (or of the list at large text sizes).
  final Key? controlKey;

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Text scale from which the vertical list replaces the segments.
  final double listThreshold;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale < listThreshold) {
      return SegmentedButton<T>(
        key: controlKey,
        segments: [for (final (value, label) in options) ButtonSegment<T>(value: value, label: Text(label))],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.first),
      );
    }
    return Column(
      key: controlKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (value, label) in options)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: value == selected,
            child: InkWell(
              onTap: () => onChanged(value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    if (value == selected) const ExcludeSemantics(child: Icon(Icons.check)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
