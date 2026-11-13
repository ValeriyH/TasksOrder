import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/l10n/l10n.dart';

/// A number with minus and plus buttons, keyed `ValueKey('$name-')` and
/// `ValueKey('$name+')`; the shown value has the key `ValueKey('$name=')`.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final String name;
  final int value;
  final int min;
  final int max;

  /// How [value] is shown.
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('$name-'),
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: l10n.actionDecrease,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 32),
          child: Text(
            label,
            key: ValueKey('$name='),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        IconButton(
          key: ValueKey('$name+'),
          icon: const Icon(Icons.add_circle_outline),
          tooltip: l10n.actionIncrease,
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
