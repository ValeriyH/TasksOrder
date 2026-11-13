import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// The badges that say why a task sits on its day: "At risk" always, and,
/// when [showReasons] is on, "Pinned", "Deadline" and "Extra".
List<Widget> planEntryBadges(
  BuildContext context,
  PlanEntry entry, {
  required bool showReasons,
}) {
  final l10n = context.l10n;
  return [
    if (entry.atRisk)
      TaskBadge(
        label: l10n.reasonAtRisk,
        color: Theme.of(context).colorScheme.error,
      ),
    if (showReasons) ...[
      if (entry.reason == PlanReason.pinned)
        TaskBadge(label: l10n.reasonPinned, icon: Icons.push_pin_outlined),
      if (entry.reason == PlanReason.deadline)
        TaskBadge(label: l10n.reasonDeadline, icon: Icons.flag_outlined),
      if (entry.overflow) TaskBadge(label: l10n.reasonOverflow),
    ],
  ];
}
