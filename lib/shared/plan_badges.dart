import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_card.dart';

/// The chips that say why a task sits on its day (D22): "At risk" always,
/// "+ Over plan" always on the Plan ([overPlan]) and with the reasons
/// elsewhere, "Deadline" when [showReasons] is on. A pin has its own chip on
/// the card. The card puts them in their places (T-1103).
List<TaskChip> planEntryChips(
  BuildContext context,
  PlanEntry entry, {
  required bool showReasons,
  bool overPlan = false,
}) {
  final l10n = context.l10n;
  return [
    if (entry.overflow && (overPlan || showReasons))
      // The text says "+": no icon (T-1103).
      TaskChip(
        label: l10n.reasonOverflow,
        tone: ChipTone.extra,
        slot: ChipSlot.overPlan,
      ),
    if (entry.atRisk)
      TaskChip(
        label: l10n.reasonAtRisk,
        icon: Icons.error_outline,
        tone: ChipTone.alert,
        slot: ChipSlot.atRisk,
      ),
    if (showReasons && entry.reason == PlanReason.deadline)
      TaskChip(
        label: l10n.reasonDeadline,
        icon: Icons.flag_outlined,
        slot: ChipSlot.deadline,
      ),
    // Lighter tasks went ahead of it (D21): the user may pin it or give a
    // day more room.
    if (entry.waitsForRoom) waitsForRoomChip(context),
  ];
}

/// "Waits for a day with room" (D21), next to the planned day of a task.
TaskChip waitsForRoomChip(BuildContext context) => TaskChip(
  key: const ValueKey('waitsForRoom'),
  label: context.l10n.reasonWaitsForRoom,
  icon: Icons.hourglass_top,
  slot: ChipSlot.waitsForRoom,
);
