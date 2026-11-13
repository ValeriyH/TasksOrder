import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/features/settings/settings_screen.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/number_stepper.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// Asks for the capacity of one [date] and an optional note, and stores the
/// answer as a day override; "As the weekday" removes the override (T-403).
///
/// [capacity] is what the date has now: the override, else the weekday.
Future<void> showDayOverrideDialog(
  BuildContext context,
  WidgetRef ref, {
  required LocalDate date,
  required int capacity,
  required DayOverride? override,
}) async {
  final repository = ref.read(dayOverrideRepositoryProvider);
  final clock = ref.read(clockProvider);

  final result = await showDialog<_Result>(
    context: context,
    builder: (context) => _DayOverrideDialog(
      date: date,
      capacity: capacity,
      note: override?.note ?? '',
      canReset: override != null,
    ),
  );
  switch (result) {
    case null:
      break;
    case _Result(reset: true):
      await repository.remove(date, clock());
    case _Result(:final capacity, :final note):
      await repository.upsert(
        DayOverride(
          date: date,
          capacity: capacity,
          note: note.isEmpty ? null : note,
        ),
        clock(),
      );
  }
}

class _Result {
  const _Result({this.capacity = 0, this.note = '', this.reset = false});

  final int capacity;
  final String note;
  final bool reset;
}

class _DayOverrideDialog extends StatefulWidget {
  const _DayOverrideDialog({
    required this.date,
    required this.capacity,
    required this.note,
    required this.canReset,
  });

  final LocalDate date;
  final int capacity;
  final String note;
  final bool canReset;

  @override
  State<_DayOverrideDialog> createState() => _DayOverrideDialogState();
}

class _DayOverrideDialogState extends State<_DayOverrideDialog> {
  late int _capacity = widget.capacity;
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.overrideTitle(shortDate(context, widget.date))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberStepper(
            name: 'override',
            value: _capacity,
            min: 0,
            max: SettingsScreen.maxCapacity,
            label: _capacity == 0
                ? l10n.capacityRestDay
                : l10n.plainNumber(_capacity),
            onChanged: (value) => setState(() => _capacity = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.overrideNoteLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _Result(reset: true)),
            child: Text(l10n.overrideReset),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context)
                  .pop(_Result(capacity: _capacity, note: _note.text.trim())),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
