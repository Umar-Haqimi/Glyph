import 'package:material_ui/material_ui.dart';

/// The heading of a settings section. A header for screen readers (they can
/// jump from heading to heading), and padded like the list tiles below it.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8)});

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        // Its own node: without it the heading merges with the text next to it
        // and a screen reader reads both as one "heading".
        container: true,
        child: Padding(
          padding: padding,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
}
