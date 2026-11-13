import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// Opens the list of the tasks that will miss their deadline (D16). The list
/// follows the plan while it is open; a tap on a task offers the ways out
/// (T-404). It closes by itself when no task is at risk any more.
Future<void> showAtRiskList(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => const _AtRiskSheet(),
);

class _AtRiskSheet extends ConsumerWidget {
  const _AtRiskSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = ref.watch(planProvider).value;
    final tasks = ref.watch(allTasksProvider).value ?? const <Task>[];
    final byId = {for (final task in tasks) task.id: task};
    final atRisk = [
      if (plan != null)
        for (final id in plan.atRiskTaskIds) ?byId[id],
    ];

    // Solved: nothing left to show.
    ref.listen(planProvider, (_, next) {
      if (next.value?.hasAtRisk == false && context.mounted) {
        Navigator.of(context).maybePop();
      }
    });

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.reasonAtRisk,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final task in atRisk)
              ListTile(
                key: ValueKey('atRisk-${task.id}'),
                title: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: switch (task.dueDate) {
                  final date? => Text(l10n.dueOn(shortDate(context, date))),
                  null => null,
                },
                trailing: const Icon(Icons.more_horiz),
                onTap: plan == null
                    ? null
                    : () => unawaited(
                        _showActions(context, ref, task, plan.today),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The ways out for one at-risk task: a later due date, one more slot today,
/// the Trash, or the editor.
Future<void> _showActions(
  BuildContext context,
  WidgetRef ref,
  Task task,
  LocalDate today,
) async {
  final l10n = context.l10n;
  final actions = ref.read(taskActionsProvider);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(l10n.dueDateMove),
            onTap: () => Navigator.of(context).pop('move'),
          ),
          ListTile(
            leading: const Icon(Icons.exposure_plus_1),
            title: Text(l10n.atRiskAddCapacity),
            onTap: () => Navigator.of(context).pop('capacity'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.actionDelete),
            onTap: () => Navigator.of(context).pop('delete'),
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
      await moveDueDate(context, ref, task, today);
    case 'capacity':
      final settings = ref.read(settingsProvider).requireValue;
      final overrides = ref.read(dayOverridesProvider).requireValue;
      final capacity = CapacityResolver(settings, overrides).capacityFor(today);
      await ref
          .read(dayOverrideRepositoryProvider)
          .upsert(
            DayOverride(
              date: today,
              capacity: capacity + 1,
              note: overrides[today]?.note,
            ),
            ref.read(clockProvider)(),
          );
    case 'delete':
      await actions.delete(task.id);
    case 'edit':
      // The editor opens over the tabs, not over this sheet.
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      unawaited(router.push(AppRoutes.task(task.id)));
  }
}
