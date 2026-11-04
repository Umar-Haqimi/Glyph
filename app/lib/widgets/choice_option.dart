import 'package:material_ui/material_ui.dart';

/// One choice of a dialog list: a button that is also a radio option for a
/// screen reader (checked + mutually exclusive group), with a visible tick.
class ChoiceOption extends StatelessWidget {
  const ChoiceOption({super.key, required this.optionKey, required this.onPressed, required this.text, required this.selected});

  final Key optionKey;
  final VoidCallback onPressed;
  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: SimpleDialogOption(
          key: optionKey,
          onPressed: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(child: Text(text)),
                if (selected) const ExcludeSemantics(child: Icon(Icons.check)),
              ],
            ),
          ),
        ),
      );
}

/// A dialog with one [ChoiceOption] per entry; returns the chosen value, or
/// null when dismissed. The dialog scrolls (24 board colours at 2x text).
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<(T value, String label)> options,
  required T selected,
  String keyPrefix = 'choice',
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          ChoiceOption(
            optionKey: Key('$keyPrefix-$value'),
            text: label,
            selected: value == selected,
            onPressed: () => Navigator.of(context).pop(value),
          ),
      ],
    ),
  );
}
