import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/plan_badges.dart';
import 'package:tasks_order/shared/screen_header.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_card.dart';

/// Which tasks the list shows.
enum TasksFilter {
  /// Every task that is not done (was "All", D22).
  active,

  /// The Focus view of the plan: focused and overdue tasks (D17, D18).
  focus,

  /// Tasks with a due date.
  due,

  /// Recurring tasks: the one active task of each series (D20).
  recurring,

  /// Tasks that do not fit the planning horizon.
  later,

  /// Completed tasks, grouped by the day they were done (T-306).
  done,
}

/// The active tasks in priority order, with the day the plan gives each, and
/// the done ones (D22).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  TasksFilter _filter = TasksFilter.active;

  /// Tasks completed while the current filter is shown: they stay in the
  /// list, done, so a tick can be taken back at leisure, until the filter or
  /// the tab changes (D22).
  final Set<String> _kept = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab is shown: the tab is kept, but its tickers stop.
    if (!TickerMode.valuesOf(context).enabled && _kept.isNotEmpty) {
      _kept.clear();
    }
  }

  void _choose(TasksFilter filter) => setState(() {
    _filter = filter;
    _kept.clear();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; without a tag of its own two of them
        // would fly as one hero when the editor opens.
        heroTag: 'tasks-add',
        tooltip: l10n.taskNewTitle,
        onPressed: () => unawaited(context.push(AppRoutes.taskNew)),
        child: const Icon(Icons.add),
      ),
      body: TabBody(
        child: switch (plan) {
          AsyncValue(:final value?) => _TasksBody(
            plan: value,
            filter: _filter,
            kept: _kept,
            onFilter: _choose,
            onCompleted: (id) => setState(() => _kept.add(id)),
          ),
          AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _TasksBody extends ConsumerWidget {
  const _TasksBody({
    required this.plan,
    required this.filter,
    required this.kept,
    required this.onFilter,
    required this.onCompleted,
  });

  final Plan plan;
  final TasksFilter filter;
  final Set<String> kept;
  final ValueChanged<TasksFilter> onFilter;
  final ValueChanged<String> onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    // The plan was computed from these, so they have arrived.
    final active = ref.watch(activeTasksProvider).requireValue;
    final later = plan.laterTaskIds.toSet();
    final focus = {for (final entry in plan.focus) entry.taskId};

    bool matches(Task task, TasksFilter filter) => switch (filter) {
      TasksFilter.active => true,
      TasksFilter.focus => focus.contains(task.id),
      TasksFilter.due => task.dueDate != null,
      TasksFilter.recurring => task.recurrence != null,
      TasksFilter.later => later.contains(task.id),
      // Done tasks have their own list.
      TasksFilter.done => false,
    };

    return Column(
      children: [
        ScreenHeader(
          subtitle: l10n.tasksActiveCount(active.length),
          title: l10n.tabTasks,
          action: IconButton(
            icon: Icon(Icons.delete_outline, color: c.title),
            tooltip: l10n.trashTitle,
            onPressed: () => unawaited(context.push(AppRoutes.trash)),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            key: const ValueKey('filters'),
            spacing: 8,
            children: [
              for (final each in TasksFilter.values)
                _FilterChip(
                  key: ValueKey('filter-${each.name}'),
                  label: switch (each) {
                    TasksFilter.active => l10n.filterActive,
                    TasksFilter.focus => l10n.taskFocusLabel,
                    TasksFilter.due => l10n.filterDue,
                    TasksFilter.recurring => l10n.filterRecurring,
                    TasksFilter.later => l10n.plannedLater,
                    TasksFilter.done => l10n.filterDone,
                  },
                  // The done ones only grow: no count (owner, D22).
                  count: each == TasksFilter.done
                      ? null
                      : active.where((task) => matches(task, each)).length,
                  selected: each == filter,
                  onTap: () => onFilter(each),
                ),
            ],
          ),
        ),
        Expanded(
          child: filter == TasksFilter.done
              ? _DoneList(today: plan.today)
              : _TaskList(
                  plan: plan,
                  tasks: [
                    for (final task in active)
                      if (matches(task, filter)) task,
                  ],
                  kept: kept,
                  onCompleted: onCompleted,
                ),
        ),
      ],
    );
  }
}

/// A filter of the Tasks screen (D22): selected with a check and a tint,
/// otherwise outlined; the count of its active tasks after the label.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final count = this.count;
    final radius = BorderRadius.circular(12);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.filterOnBg : c.filterOffBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide.none
              : BorderSide(color: c.filterOffBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 16, color: c.filterOnFg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? c.filterOnFg : c.filterOffFg,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? c.filterCountOn : c.filterCountOff,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({
    required this.plan,
    required this.tasks,
    required this.kept,
    required this.onCompleted,
  });

  final Plan plan;

  /// The active tasks of the filter.
  final List<Task> tasks;

  /// Done while the filter is shown: they stay at the end.
  final Set<String> kept;
  final ValueChanged<String> onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final all = ref.watch(allTasksProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final scale = settings.priorityScale;
    final today = plan.today;
    final paused = ref.watch(pausedTaskIdsProvider);
    final older = ref.watch(olderCompletionIdsProvider);

    // The day of the task itself: the ghosts of a recurring task (T-704)
    // carry its id too, and the last of them would win.
    final plannedDate = <String, LocalDate>{
      for (final day in plan.days)
        for (final entry in day.entries)
          if (!entry.isGhost) entry.taskId: day.date,
    };
    // Lighter tasks went ahead of these (D21).
    final waiting = {
      for (final day in plan.days)
        for (final entry in day.entries)
          if (!entry.isGhost && entry.waitsForRoom) entry.taskId,
    };

    final sorted = [...tasks]
      ..sort((a, b) => Planner.compareForList(a, b, today: today));
    final done = [
      for (final task in all)
        if (kept.contains(task.id) && task.isDone && !task.isDeleted) task,
    ]..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    final rows = [...sorted, ...done];

    if (rows.isEmpty) return _Empty(color: c.muted, text: l10n.tasksEmpty);

    return ListView.builder(
      // Room for the add button and the navigation below the last card.
      padding: const EdgeInsets.only(bottom: AppDims.listBottomPadding),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final task = rows[index];
        if (task.isDone) {
          return TaskCard(
            key: ValueKey(task.id),
            task: task,
            scale: scale,
            today: today,
            isDone: true,
            doneOn: Planner.completionDay(task, settings.dayStartHour),
            locked: older.contains(task.id),
            onTap: () => unawaited(context.push(AppRoutes.task(task.id))),
            onToggleDone: () => unawaited(
              toggleDone(
                context,
                ref,
                task,
                onPlan: false,
                plannedDate: null,
                isDone: true,
              ),
            ),
          );
        }

        final date = plannedDate[task.id];
        // On today's list: a completion uses up its slot (D19).
        final onPlan = date == today;

        Future<void> complete() async {
          // A paused task (T-710) is not completed; the hint says why.
          final completes = !paused.contains(task.id);
          await toggleDone(
            context,
            ref,
            task,
            onPlan: onPlan,
            plannedDate: date,
            isDone: false,
          );
          if (completes) onCompleted(task.id);
        }

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
          // The swipe only triggers the action and the card slides back.
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await complete();
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
          child: TaskCard(
            task: task,
            scale: scale,
            today: today,
            paused: paused.contains(task.id),
            // The planned chip says the day (T-911).
            showPinDate: false,
            onTap: () => unawaited(showTaskMenu(context, ref, task, today)),
            onToggleDone: () => unawaited(complete()),
            chips: [
              TaskChip(
                label: switch (date) {
                  null => l10n.plannedLater,
                  _ when onPlan => l10n.plannedToday,
                  final date => l10n.plannedFor(shortDate(context, date)),
                },
                icon: Icons.calendar_today_outlined,
              ),
              if (waiting.contains(task.id)) waitsForRoomChip(context),
            ],
          ),
        );
      },
    );
  }
}

/// Nothing in a filter (D22): the list icon and a line.
class _Empty extends StatelessWidget {
  const _Empty({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.checklist, size: 40, color: color),
        const SizedBox(height: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

/// Completed tasks, the latest first, under a header for each day. A tap on
/// "Completed" returns the task to the active ones; an older completion of
/// a series cannot come back (T-713).
class _DoneList extends ConsumerWidget {
  const _DoneList({required this.today});

  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final settings = ref.watch(settingsProvider).requireValue;
    final scale = settings.priorityScale;
    final older = ref.watch(olderCompletionIdsProvider);
    final done =
        ref
            .watch(allTasksProvider)
            .requireValue
            .where((task) => task.isDone)
            .toList()
          ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

    if (done.isEmpty) return _Empty(color: c.muted, text: l10n.tasksEmpty);

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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Text(
              switch (day.daysUntil(today)) {
                0 => l10n.dateToday,
                1 => l10n.dateYesterday,
                _ => shortDate(context, day),
              },
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        );
      }
      rows.add(
        TaskCard(
          key: ValueKey(task.id),
          task: task,
          scale: scale,
          today: today,
          isDone: true,
          doneOn: day,
          locked: older.contains(task.id),
          onTap: () => unawaited(context.push(AppRoutes.task(task.id))),
          onToggleDone: () => unawaited(
            toggleDone(
              context,
              ref,
              task,
              onPlan: false,
              plannedDate: null,
              isDone: true,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppDims.listBottomPadding),
      children: rows,
    );
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
    return Padding(
      padding: AppDims.cardMargin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppDims.cardRadius),
        ),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Icon(icon, color: iconColor),
          ),
        ),
      ),
    );
  }
}
