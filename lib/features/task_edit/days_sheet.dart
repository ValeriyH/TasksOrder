import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/repeat_text.dart';

/// What the days sheet returns: [days] null means "any day".
final class DaysChoice {
  const DaysChoice(this.days);

  /// One to six weekdays, Monday = 0; null for no limit.
  final Set<int>? days;
}

/// Asks on which days of the week the task may be planned (D23, T-1005).
/// Returns null when the sheet is dismissed or cancelled. No day chosen and
/// all seven chosen both mean "any day".
Future<DaysChoice?> showDaysSheet(
  BuildContext context, {
  required Set<int>? current,
}) => showModalBottomSheet<DaysChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _DaysSheet(current: current),
);

class _DaysSheet extends StatefulWidget {
  const _DaysSheet({required this.current});

  final Set<int>? current;

  @override
  State<_DaysSheet> createState() => _DaysSheetState();
}

class _DaysSheetState extends State<_DaysSheet> {
  late final Set<int> _days = {...?widget.current};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final limited = _days.isNotEmpty && _days.length < 7;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.daysSheetTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              l10n.daysSheetHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var day = 0; day < 7; day++)
                  FilterChip(
                    key: ValueKey('allowedDay$day'),
                    label: Text(shortWeekday(l10n, day)),
                    selected: _days.contains(day),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _days.add(day);
                      } else {
                        _days.remove(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  key: const ValueKey('daysAny'),
                  onPressed: _days.isEmpty ? null : () => setState(_days.clear),
                  child: Text(l10n.taskDaysAny),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('daysDone'),
                  onPressed: () =>
                      Navigator.of(context)
                          .pop(DaysChoice(limited ? {..._days} : null)),
                  child: Text(l10n.actionDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
