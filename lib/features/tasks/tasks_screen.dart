import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// Which tasks the list shows.
enum TasksFilter {
  all,

  /// The Focus view of the plan: focused and overdue tasks (D17, D18).
  focus,

  /// Tasks with a due date.
  due,

  /// Tasks that do not fit the planning horizon.
  later,

  /// Completed tasks, grouped by the day they were done (T-306).
  done,
}

/// All active tasks in priority order, with the day the plan gives each.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  TasksFilter _filter = TasksFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabTasks),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.trashTitle,
            onPressed: () => unawaited(context.push(AppRoutes.trash)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; without a tag of its own two of them
        // would fly as one hero when the editor opens.
        heroTag: 'tasks-add',
        tooltip: l10n.taskNewTitle,
        onPressed: () => unawaited(context.push(AppRoutes.taskNew)),
        child: const Icon(Icons.add),
      ),
      body: switch (plan) {
        AsyncValue(:final value?) => Column(
          children: [
            _FilterBar(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            Expanded(
              child: _TaskList(plan: value, filter: _filter),
            ),
          ],
        ),
        AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final TasksFilter selected;
  final ValueChanged<TasksFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          for (final filter in TasksFilter.values)
            ChoiceChip(
              label: Text(switch (filter) {
                TasksFilter.all => l10n.filterAll,
                TasksFilter.focus => l10n.taskFocusLabel,
                TasksFilter.due => l10n.filterDue,
                TasksFilter.later => l10n.plannedLater,
                TasksFilter.done => l10n.filterDone,
              }),
              selected: filter == selected,
              onSelected: (_) => onSelected(filter),
            ),
        ],
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.plan, required this.filter});

  final Plan plan;
  final TasksFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filter == TasksFilter.done) return _DoneList(today: plan.today);

    final l10n = context.l10n;
    final theme = Theme.of(context);
    // The plan was computed from these, so they have arrived.
    final active = ref.watch(activeTasksProvider).requireValue;
    final scale = ref.watch(settingsProvider).requireValue.priorityScale;
    final today = plan.today;

    final plannedDate = <String, LocalDate>{
      for (final day in plan.days)
        for (final entry in day.entries) entry.taskId: day.date,
    };
    final later = plan.laterTaskIds.toSet();
    final focus = {for (final entry in plan.focus) entry.taskId};

    final tasks = [
      for (final task in active)
        if (switch (filter) {
          TasksFilter.all => true,
          TasksFilter.focus => focus.contains(task.id),
          TasksFilter.due => task.dueDate != null,
          TasksFilter.later => later.contains(task.id),
          // Done tasks have their own list.
          TasksFilter.done => false,
        })
          task,
    ]..sort((a, b) => Planner.compareForList(a, b, today: today));

    if (tasks.isEmpty) {
      return Center(
        child: Text(l10n.tasksEmpty, style: theme.textTheme.titleMedium),
      );
    }

    return ListView.builder(
      // Room for the button above the last task.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final date = plannedDate[task.id];
        // On today's list: a completion uses up its slot (D19).
        final onPlan = date == today;

        Future<void> toggleFocus() async {
          final messenger = ScaffoldMessenger.of(context);
          final value = !task.isFocused;
          await ref.read(taskActionsProvider).setFocus(task.id, value);
          unawaited(HapticFeedback.selectionClick());
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(value ? l10n.focusOn : l10n.focusOff)),
            );
        }

        return Dismissible(
          key: ValueKey(task.id),
          // The swipe only triggers the action and the row slides back; a
          // completed task leaves the list when the database reports it.
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await completeWithUndo(context, ref, task, onPlan: onPlan);
            } else {
              await toggleFocus();
            }
            return false;
          },
          background: _SwipeBackground(
            icon: Icons.check,
            alignment: AlignmentDirectional.centerStart,
            color: theme.colorScheme.primaryContainer,
            iconColor: theme.colorScheme.onPrimaryContainer,
          ),
          secondaryBackground: _SwipeBackground(
            icon: task.isFocused
                ? Icons.center_focus_weak
                : Icons.center_focus_strong,
            alignment: AlignmentDirectional.centerEnd,
            color: theme.colorScheme.secondaryContainer,
            iconColor: theme.colorScheme.onSecondaryContainer,
          ),
          child: TaskTile(
            task: task,
            scale: scale,
            today: today,
            onTap: () => unawaited(context.push(AppRoutes.task(task.id))),
            onCompleted: () =>
                unawaited(completeWithUndo(context, ref, task, onPlan: onPlan)),
            onMoveDueDate: () =>
                unawaited(moveDueDate(context, ref, task, today)),
            onClearDueDate: () =>
                unawaited(ref.read(taskActionsProvider).setDueDate(task, null)),
            badges: [
              TaskBadge(
                label: switch (date) {
                  null => l10n.plannedLater,
                  _ when onPlan => l10n.plannedToday,
                  final date => l10n.plannedFor(shortDate(context, date)),
                },
                icon: Icons.schedule,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Completed tasks, the latest first, under a header for each day. A tap on
/// the checkbox returns the task to the active ones.
class _DoneList extends ConsumerWidget {
  const _DoneList({required this.today});

  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider).requireValue;
    final scale = settings.priorityScale;
    final done =
        ref
            .watch(allTasksProvider)
            .requireValue
            .where((task) => task.isDone)
            .toList()
          ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

    if (done.isEmpty) {
      return Center(
        child: Text(l10n.tasksEmpty, style: theme.textTheme.titleMedium),
      );
    }

    // The day of a completion follows the day start of the settings (D15).
    LocalDate dayOf(Task task) =>
        LocalDate.todayFor(task.completedAt!.toLocal(), settings.dayStartHour);

    final rows = <Widget>[];
    LocalDate? header;
    for (final task in done) {
      final day = dayOf(task);
      if (day != header) {
        header = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              switch (day.daysUntil(today)) {
                0 => l10n.dateToday,
                1 => l10n.dateYesterday,
                _ => shortDate(context, day),
              },
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final priority = math.min(task.priority, scale);
      rows.add(
        ListTile(
          key: ValueKey(task.id),
          onTap: () => unawaited(context.push(AppRoutes.task(task.id))),
          leading: Checkbox(
            value: true,
            onChanged: (_) =>
                unawaited(ref.read(taskActionsProvider).uncomplete(task.id)),
          ),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: TextDecoration.lineThrough,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          subtitle: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TaskBadge(
                label: priorityLabel(l10n, priority, scale),
                dotColor: priorityColor(priority, scale),
              ),
            ),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.only(bottom: 88), children: rows);
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.alignment,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final AlignmentGeometry alignment;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Icon(icon, color: iconColor),
        ),
      ),
    );
  }
}
