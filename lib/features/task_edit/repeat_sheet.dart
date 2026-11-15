import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/number_stepper.dart';
import 'package:tasks_order/shared/repeat_text.dart';

/// What the repeat sheet returns: [rule] null means "does not repeat".
final class RepeatChoice {
  const RepeatChoice(this.rule);

  final Recurrence? rule;
}

/// Asks how the task repeats (D20, T-707). Returns null when the sheet is
/// dismissed or cancelled.
///
/// A rule by schedule gets [current]'s anchor when it had one, else
/// [anchor]; `Task.setRecurrence` anchors it on the task's dates anyway. Done
/// without a change gives back [current] itself.
Future<RepeatChoice?> showRepeatSheet(
  BuildContext context, {
  required Recurrence? current,
  required LocalDate anchor,
}) => showModalBottomSheet<RepeatChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _RepeatSheet(current: current, anchor: anchor),
);

enum _Kind { none, interval, weekdays }

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.current, required this.anchor});

  final Recurrence? current;
  final LocalDate anchor;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  static const _maxEvery = 99;

  late _Kind _kind;
  int _every = 1;
  RecurrenceUnit _unit = RecurrenceUnit.week;
  bool _afterDone = false;
  late Set<int> _days;

  @override
  void initState() {
    super.initState();
    _days = {widget.anchor.weekday};
    switch (widget.current) {
      case null:
        _kind = _Kind.none;
      case IntervalRecurrence(:final every, :final unit, :final afterDone):
        _kind = _Kind.interval;
        _every = every;
        _unit = unit;
        _afterDone = afterDone;
      case WeekdaysRecurrence(:final days):
        _kind = _Kind.weekdays;
        _days = {...days};
    }
  }

  Recurrence? _build() {
    final current = widget.current;
    final Recurrence? rule = switch (_kind) {
      _Kind.none => null,
      _Kind.interval => Recurrence.interval(
        every: _every,
        unit: _unit,
        afterDone: _afterDone,
        anchor: _afterDone
            ? null
            : current is IntervalRecurrence
            ? current.anchor ?? widget.anchor
            : widget.anchor,
      ),
      _Kind.weekdays => Recurrence.weekdays(_days),
    };
    return rule == current ? current : rule;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

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
            Text(l10n.repeatTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<_Kind>(
              key: const ValueKey('repeatKind'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _Kind.none,
                  label: Text(l10n.repeatKindNone),
                ),
                ButtonSegment(
                  value: _Kind.interval,
                  label: Text(l10n.repeatKindInterval),
                ),
                ButtonSegment(
                  value: _Kind.weekdays,
                  label: Text(l10n.repeatKindWeekdays),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.single),
            ),
            const SizedBox(height: 16),
            if (_kind == _Kind.interval) ...[
              Row(
                children: [
                  Text(l10n.repeatEveryLabel),
                  const SizedBox(width: 8),
                  NumberStepper(
                    name: 'repeatEvery',
                    value: _every,
                    min: 1,
                    max: _maxEvery,
                    label: l10n.plainNumber(_every),
                    onChanged: (value) => setState(() => _every = value),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<RecurrenceUnit>(
                    key: const ValueKey('repeatUnit'),
                    value: _unit,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final unit in RecurrenceUnit.values)
                        DropdownMenuItem(
                          value: unit,
                          child: Text(unitName(l10n, unit, _every)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _unit = value);
                    },
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('repeatAfterDone'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.repeatAfterDone),
                subtitle: Text(l10n.repeatAfterDoneHint),
                value: _afterDone,
                onChanged: (value) => setState(() => _afterDone = value),
              ),
            ],
            if (_kind == _Kind.weekdays)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var day = 0; day < 7; day++)
                    FilterChip(
                      key: ValueKey('repeatDay$day'),
                      label: Text(shortWeekday(l10n, day)),
                      selected: _days.contains(day),
                      // The last chosen day stays: a rule needs one.
                      onSelected: (on) => setState(() {
                        if (on) {
                          _days.add(day);
                        } else if (_days.length > 1) {
                          _days.remove(day);
                        }
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('repeatDone'),
                  onPressed: () =>
                      Navigator.of(context).pop(RepeatChoice(_build())),
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
