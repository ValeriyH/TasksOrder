import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/features/plan/day_override_dialog.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/at_risk_sheet.dart';
import 'package:tasks_order/shared/plan_badges.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// The coming days of the plan: which task lands on which day, and why.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabPlan)),
      body: switch (plan) {
        AsyncValue(:final value?) => _PlanBody(plan: value),
        AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // The plan was computed from these, so they have arrived.
    final tasks = ref.watch(allTasksProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final overrides = ref.watch(dayOverridesProvider).requireValue;
    final showReasons = ref.watch(
      deviceSettingsProvider.select((settings) => settings.showReasons),
    );

    final byId = {for (final task in tasks) task.id: task};
    final today = plan.today;
    final scale = settings.priorityScale;
    final resolver = CapacityResolver(settings, overrides);
    // Today counts what was done from its list too, against the full
    // capacity: the numbers of the Today screen.
    final doneToday = Planner.countCompletedToday(
      tasks,
      today: today,
      dayStartHour: settings.dayStartHour,
    );

    TaskTile tile(Task task, {required bool onPlan, List<Widget>? badges}) =>
        TaskTile(
          key: ValueKey(task.id),
          task: task,
          scale: scale,
          today: today,
          badges: badges ?? const [],
          onTap: () => unawaited(context.push(AppRoutes.task(task.id))),
          onLongPress: () =>
              unawaited(_showTaskMenu(context, ref, task, today)),
          onCompleted: () =>
              unawaited(completeWithUndo(context, ref, task, onPlan: onPlan)),
          onMoveDueDate: () =>
              unawaited(moveDueDate(context, ref, task, today)),
          onClearDueDate: () =>
              unawaited(ref.read(taskActionsProvider).setDueDate(task, null)),
        );

    final later = [for (final id in plan.laterTaskIds) ?byId[id]];

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (plan.hasAtRisk)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                title: Text(
                  l10n.planAtRisk(plan.atRiskTaskIds.length),
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onErrorContainer,
                ),
                onTap: () => unawaited(showAtRiskList(context)),
              ),
            ),
          ),
        for (final day in plan.days) ...[
          _DayHeader(
            day: day,
            today: today,
            count: day.entries.length + (day.date == today ? doneToday : 0),
            capacity: resolver.capacityFor(day.date),
            dayOverride: overrides[day.date],
            onTap: () => unawaited(
              showDayOverrideDialog(
                context,
                ref,
                date: day.date,
                capacity: resolver.capacityFor(day.date),
                override: overrides[day.date],
              ),
            ),
          ),
          for (final entry in day.entries)
            if (byId[entry.taskId] case final task?)
              tile(
                task,
                onPlan: day.date == today,
                badges: planEntryBadges(
                  context,
                  entry,
                  showReasons: showReasons,
                ),
              ),
        ],
        if (later.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              l10n.planLater(later.length),
              key: const ValueKey('later'),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final task in later) tile(task, onPlan: false),
        ],
      ],
    );
  }
}

/// The date of a day, how full it is, and a tap target that changes its
/// capacity. Keyed `ValueKey('day-<iso date>')`.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.today,
    required this.count,
    required this.capacity,
    required this.dayOverride,
    required this.onTap,
  });

  final PlannedDay day;
  final LocalDate today;

  /// Tasks the day holds; for today the ones done from its list too.
  final int count;

  /// The day's full capacity. At 0 (a rest day) the header reads "Rest day"
  /// like the steppers of Settings, unless a pinned task is on it.
  final int capacity;

  /// The capacity set for this date, when there is one.
  final DayOverride? dayOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final overloaded = day.isOverloaded;
    final countColor = overloaded
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final note = dayOverride?.note;

    return InkWell(
      key: ValueKey('day-${day.date.toIso()}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: switch (today.daysUntil(day.date)) {
                    0 => l10n.dateToday,
                    1 => l10n.dateTomorrow,
                    _ => shortDate(context, day.date),
                  },
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                  children: [
                    if (note != null && note.isNotEmpty)
                      TextSpan(
                        text: '  $note',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (dayOverride != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: l10n.planChangedCapacity,
                  child: Icon(Icons.tune, size: 16, color: countColor),
                ),
              ),
            if (overloaded)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: l10n.planOverloaded,
                  child: Icon(Icons.error_outline, size: 16, color: countColor),
                ),
              ),
            Text(
              capacity == 0 && count == 0
                  ? l10n.capacityRestDay
                  : l10n.planDayCount(count, capacity),
              style: theme.textTheme.bodyMedium?.copyWith(color: countColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a long press on a planned task offers: fix it to a day, release it,
/// or open the editor (T-402).
Future<void> _showTaskMenu(
  BuildContext context,
  WidgetRef ref,
  Task task,
  LocalDate today,
) async {
  final actions = ref.read(taskActionsProvider);
  final l10n = context.l10n;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(l10n.pinMove),
            onTap: () => Navigator.of(context).pop('move'),
          ),
          if (task.pinnedDate != null)
            ListTile(
              leading: const Icon(Icons.push_pin),
              title: Text(l10n.pinRemove),
              onTap: () => Navigator.of(context).pop('unpin'),
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.actionEdit),
            onTap: () => Navigator.of(context).pop('edit'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'move':
      final pinned = task.pinnedDate;
      final picked = await showDatePicker(
        context: context,
        initialDate: dateTimeOf(
          pinned != null && pinned >= today ? pinned : today,
        ),
        firstDate: dateTimeOf(today),
        lastDate: DateTime(today.year + 10, 12, 31),
      );
      if (picked != null) {
        await actions.setPinnedDate(task, LocalDate.fromDateTime(picked));
      }
    case 'unpin':
      await actions.setPinnedDate(task, null);
    case 'edit':
      unawaited(context.push(AppRoutes.task(task.id)));
  }
}
