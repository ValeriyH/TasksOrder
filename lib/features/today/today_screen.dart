import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/features/today/quick_add_sheet.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/at_risk_sheet.dart';
import 'package:tasks_order/shared/plan_badges.dart';
import 'package:tasks_order/shared/screen_header.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_card.dart';

/// What to do today (D22): the date, the progress of today's list, the
/// Focus section and today's list of the plan. Tasks done today stay at the
/// end of their section until the day ends.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; without a tag of its own two of them
        // would fly as one hero when the editor opens.
        heroTag: 'today-add',
        tooltip: l10n.taskNewTitle,
        onPressed: () => unawaited(showQuickAdd(context)),
        child: const Icon(Icons.add),
      ),
      body: TabBody(
        child: switch (plan) {
          AsyncValue(:final value?) => _TodayBody(plan: value),
          AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// "Sunday, 15 November": the weekday with a capital, the day and the month
/// (the form a date takes in a sentence, so the genitive in Ukrainian).
String fullDayName(BuildContext context, LocalDate date) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final text = DateFormat('EEEE, d MMMM', locale).format(dateTimeOf(date));
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    // The plan was computed from these, so they have arrived.
    final tasks = ref.watch(allTasksProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final overrides = ref.watch(dayOverridesProvider).requireValue;
    final showReasons = ref.watch(
      deviceSettingsProvider.select((settings) => settings.showReasons),
    );

    final paused = ref.watch(pausedTaskIdsProvider);
    final older = ref.watch(olderCompletionIdsProvider);
    final byId = {for (final task in tasks) task.id: task};
    final today = plan.today;
    final day = plan.days.first;
    final scale = settings.priorityScale;
    final capacity = CapacityResolver(settings, overrides).capacityFor(today);

    // Done today, in the order they were done. From today's list they stay
    // in Planned (D19); from the Focus section (focused or overdue, D17,
    // D18) they stay in Focus. Others were done elsewhere for another day.
    final doneToday = [
      for (final task in tasks)
        if (!task.isDeleted &&
            Planner.completedOn(task, today, settings.dayStartHour))
          task,
    ]..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    // Done today from today's list: the plan had them on today (T-907), or,
    // stored before schema 4, the completion says so (D19).
    final donePlanned = [
      for (final task in doneToday)
        if (Planner.keptOnDay(
          task,
          today,
          today: today,
          dayStartHour: settings.dayStartHour,
        ))
          task,
    ];
    final doneFocus = [
      for (final task in doneToday)
        if (!donePlanned.contains(task) &&
            (task.isFocused || _overdue(task, today)))
          task,
    ];
    // The numbers of the plan (D19), deleted ones included: the work was
    // done today.
    final doneCount = Planner.countCompletedToday(
      tasks,
      today: today,
      dayStartHour: settings.dayStartHour,
    );

    Widget card(
      Task task, {
      required LocalDate? plannedDate,
      bool isDone = false,
      List<Widget> chips = const [],
    }) => TaskCard(
      key: ValueKey(task.id),
      task: task,
      scale: scale,
      today: today,
      isDone: isDone,
      doneOn: isDone ? today : null,
      paused: !isDone && paused.contains(task.id),
      locked: isDone && older.contains(task.id),
      // Today has its own Focus section (D22).
      showFocus: false,
      chips: chips,
      onTap: () => unawaited(showTaskMenu(context, ref, task, today)),
      onToggleDone: () => unawaited(
        toggleDone(
          context,
          ref,
          task,
          onPlan: plannedDate == today,
          plannedDate: plannedDate,
          isDone: isDone,
        ),
      ),
    );

    final focus = [
      for (final entry in plan.visibleFocus)
        if (byId[entry.taskId] case final task?)
          card(
            task,
            plannedDate: entry.plannedDate,
            chips: [
              TaskChip(
                label: switch (entry.plannedDate) {
                  final date? => l10n.plannedFor(shortDate(context, date)),
                  null => l10n.plannedLater,
                },
                icon: Icons.calendar_today_outlined,
              ),
            ],
          ),
      for (final task in doneFocus)
        card(task, plannedDate: task.completedPlanDate, isDone: true),
    ];
    final focusActive = plan.visibleFocus.length + plan.hiddenFocusCount;
    final planned = [
      for (final entry in day.entries)
        if (byId[entry.taskId] case final task?)
          card(
            task,
            plannedDate: today,
            chips: planEntryChips(context, entry, showReasons: showReasons),
          ),
    ];
    final plannedTotal = planned.length + doneCount;

    final atRisk = [for (final id in plan.atRiskTaskIds) ?byId[id]];

    return ListView(
      // Room for the add button and the navigation below the last card.
      padding: const EdgeInsets.only(bottom: AppDims.listBottomPadding),
      children: [
        ScreenHeader(
          subtitle: fullDayName(context, today),
          title: l10n.tabToday,
          bottom: DayProgress(
            done: doneCount,
            total: plannedTotal,
            label: l10n.todayProgress(doneCount, plannedTotal),
          ),
        ),
        if (atRisk.isNotEmpty)
          _Banner(
            icon: Icons.warning_amber_rounded,
            text: l10n.todayAtRisk(atRisk.length),
            background: c.capOverBg,
            foreground: c.capOverFg,
            onTap: () => unawaited(showAtRiskList(context)),
          ),
        if (day.isOverloaded)
          _Banner(
            icon: Icons.error_outline,
            // All the day holds, the ones done from the list too, against
            // its full capacity: the numbers of the progress.
            text: l10n.todayOverloaded(plannedTotal, capacity),
            background: c.extraChipBg,
            foreground: c.extraChipFg,
          ),
        if (focus.isNotEmpty) ...[
          SectionHeader(
            icon: Icons.center_focus_strong_outlined,
            title: l10n.taskFocusLabel,
            // How many tasks are in Focus; the list shows the first
            // three and "+N more" (owner, D22).
            counter: '$focusActive',
          ),
          ...focus,
          if (plan.hiddenFocusCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.focusMore(plan.hiddenFocusCount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
        ],
        if (plannedTotal > 0) ...[
          SectionHeader(
            icon: Icons.today_outlined,
            title: l10n.todayPlanned,
            counter: l10n.sectionCount(doneCount, plannedTotal),
          ),
          ...planned,
          for (final task in donePlanned)
            card(task, plannedDate: today, isDone: true),
        ],
        if (planned.isEmpty) _EmptyDay(allDone: doneCount > 0, tasks: tasks),
      ],
    );
  }
}

/// Nothing left on today's list: done, or nothing was planned.
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.allDone, required this.tasks});

  final bool allDone;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
      child: Column(
        children: [
          Icon(
            allDone ? Icons.celebration_outlined : Icons.wb_sunny_outlined,
            size: 48,
            color: c.muted,
          ),
          const SizedBox(height: 12),
          Text(
            allDone ? l10n.todayAllDone : l10n.todayEmpty,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: c.title,
            ),
            textAlign: TextAlign.center,
          ),
          if (!tasks.any((task) => !task.isDone)) ...[
            const SizedBox(height: 8),
            Text(
              l10n.todayEmptyHint,
              style: TextStyle(fontSize: 14, color: c.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Its due date had passed (D18): it was in Focus as overdue.
bool _overdue(Task task, LocalDate today) {
  final due = task.dueDate;
  return due != null && due < today;
}
