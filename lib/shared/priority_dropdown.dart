import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';

/// The middle of the scale: what a new task gets ("Normal" on every scale).
int defaultPriority(int scale) => (scale + 1) ~/ 2;

/// A form field that picks a priority of the given [scale]; the items read
/// "Label (n)" with the colour of the level (D1).
class PriorityDropdown extends StatelessWidget {
  const PriorityDropdown({
    required this.scale,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The priority scale of the settings: 3, 5 or 10.
  final int scale;

  /// The selected priority, in `1..scale`.
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<int>(
      // A new scale has other items.
      key: ValueKey(scale),
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.taskPriorityLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var p = 1; p <= scale; p++)
          DropdownMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: priorityColor(p, scale)),
                const SizedBox(width: 12),
                Text(priorityLabel(l10n, p, scale)),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
