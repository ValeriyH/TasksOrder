import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_card.dart';

/// The chips that say why a task sits on its day (D22): "At risk" always,
/// "Over plan" always on the Plan ([overPlan]) and with the reasons
/// elsewhere, "Deadline" when [showReasons] is on. A pin has its own chip on
/// the card.
List<Widget> planEntryChips(
  BuildContext context,
  PlanEntry entry, {
  required bool showReasons,
  bool overPlan = false,
}) {
  final l10n = context.l10n;
  return [
    if (entry.overflow && (overPlan || showReasons))
      TaskChip(
        label: l10n.reasonOverflow,
        icon: Icons.add,
        tone: ChipTone.extra,
      ),
    if (entry.atRisk)
      TaskChip(
        label: l10n.reasonAtRisk,
        icon: Icons.error_outline,
        tone: ChipTone.alert,
      ),
    if (showReasons && entry.reason == PlanReason.deadline)
      TaskChip(label: l10n.reasonDeadline, icon: Icons.flag_outlined),
    // Lighter tasks went ahead of it (D21): the user may pin it or give a
    // day more room.
    if (entry.waitsForRoom) waitsForRoomChip(context),
  ];
}

/// "Waits for a day with room" (D21), next to the planned day of a task.
Widget waitsForRoomChip(BuildContext context) => TaskChip(
  key: const ValueKey('waitsForRoom'),
  label: context.l10n.reasonWaitsForRoom,
  icon: Icons.hourglass_top,
);
