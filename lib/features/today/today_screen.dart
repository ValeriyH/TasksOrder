import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/features/today/quick_add_sheet.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/at_risk_sheet.dart';
import 'package:tasks_order/shared/plan_badges.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// What to do today: the Focus strip and today's list of the plan.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabToday)),
      floatingActionButton: FloatingActionButton(
        // Each tab has its own button; without a tag of its own two of them
        // would fly as one hero when the editor opens.
        heroTag: 'today-add',
        tooltip: l10n.taskNewTitle,
        onPressed: () => unawaited(showQuickAdd(context)),
        child: const Icon(Icons.add),
      ),
      body: switch (plan) {
        AsyncValue(:final value?) => _TodayBody(plan: value),
        AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TodayBody extends ConsumerWidget {
  const _TodayBody({required this.plan});

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
    final day = plan.days.first;
    final scale = settings.priorityScale;
    final capacity = CapacityResolver(settings, overrides).capacityFor(today);
    final doneCount = Planner.countCompletedToday(
      tasks,
      today: today,
      dayStartHour: settings.dayStartHour,
    );

    void edit(Task task) => unawaited(context.push(AppRoutes.task(task.id)));

    TaskTile tile(Task task, {required bool onPlan, List<Widget>? badges}) =>
        TaskTile(
          key: ValueKey(task.id),
          task: task,
          scale: scale,
          today: today,
          badges: badges ?? const [],
          onTap: () => edit(task),
          onCompleted: () =>
              unawaited(completeWithUndo(context, ref, task, onPlan: onPlan)),
          onMoveDueDate: () =>
              unawaited(moveDueDate(context, ref, task, today)),
          onClearDueDate: () =>
              unawaited(ref.read(taskActionsProvider).setDueDate(task, null)),
        );

    final focus = [
      for (final entry in plan.visibleFocus)
        if (byId[entry.taskId] case final task?)
          tile(
            task,
            onPlan: false,
            badges: [
              TaskBadge(
                label: switch (entry.plannedDate) {
                  final date? => l10n.plannedFor(shortDate(context, date)),
                  null => l10n.plannedLater,
                },
                icon: Icons.schedule,
              ),
            ],
          ),
    ];
    final planned = [
      for (final entry in day.entries)
        if (byId[entry.taskId] case final task?)
          tile(
            task,
            onPlan: true,
            badges: planEntryBadges(context, entry, showReasons: showReasons),
          ),
    ];

    final atRisk = [for (final id in plan.atRiskTaskIds) ?byId[id]];

    return ListView(
      // Room for the button below the last task.
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (atRisk.isNotEmpty)
          _Banner(
            icon: Icons.warning_amber_rounded,
            text: l10n.todayAtRisk(atRisk.length),
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
            onTap: () => unawaited(showAtRiskList(context)),
          ),
        if (day.isOverloaded)
          _Banner(
            icon: Icons.info_outline,
            text: l10n.todayOverloaded(day.entries.length, day.capacity),
            background: theme.colorScheme.tertiaryContainer,
            foreground: theme.colorScheme.onTertiaryContainer,
          ),
        if (focus.isNotEmpty) ...[
          _SectionHeader(title: l10n.taskFocusLabel),
          ...focus,
          if (plan.hiddenFocusCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                l10n.focusMore(plan.hiddenFocusCount),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        if (planned.isNotEmpty || doneCount > 0) ...[
          _SectionHeader(
            title: l10n.todayPlannedHeader(planned.length, capacity),
            trailing: doneCount > 0 ? l10n.todayDoneCount(doneCount) : null,
          ),
          ...planned,
        ],
        if (planned.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Column(
              children: [
                Icon(
                  doneCount > 0
                      ? Icons.celebration_outlined
                      : Icons.wb_sunny_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  doneCount > 0 ? l10n.todayAllDone : l10n.todayEmpty,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (!tasks.any((task) => !task.isDone)) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.todayEmptyHint,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (trailing case final text?)
            Text(text, style: theme.textTheme.bodySmall),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
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
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: foreground),
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
