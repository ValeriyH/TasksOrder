import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';

/// A form field that picks one of the levels of [scale]; the items show the
/// name with the colour of the level (D1, ADR-17).
class PriorityDropdown extends StatelessWidget {
  const PriorityDropdown({
    required this.scale,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// The priority scale of the settings: 3, 5 or 10.
  final int scale;

  /// The priority of the task. A level the scale does not offer shows as the
  /// nearest one it does, and stays as it is until the user picks another.
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<int>(
      // A new scale has other items.
      key: ValueKey(scale),
      initialValue: PriorityLabels.nearest(value, scale),
      decoration: InputDecoration(
        labelText: l10n.taskPriorityLabel,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final p in PriorityLabels.levels(scale))
          DropdownMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: priorityColor(p, scale)),
                const SizedBox(width: 12),
                Text(priorityName(l10n, p, scale)),
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
