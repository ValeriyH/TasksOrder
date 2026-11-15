import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_card.dart';

/// How long a message with "Undo" stays on screen.
const undoSnackBarDuration = Duration(seconds: 4);

/// A message with an "Undo" button that goes away by itself after
/// [undoSnackBarDuration]. Flutter keeps a snackbar with an action until it is
/// closed unless it is told otherwise (`persist`).
SnackBar undoSnackBar({
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) => SnackBar(
  content: Text(message),
  duration: undoSnackBarDuration,
  persist: false,
  action: SnackBarAction(label: undoLabel, onPressed: onUndo),
);

/// The Done button of a card on a list that keeps done tasks in sight
/// (D22): completes the task, or, when it is done ([isDone]), returns it.
/// No "Undo" snackbar: the card itself undoes. A task paused until tomorrow
/// (T-710) is not completed; a snackbar says why.
///
/// [onPlan]: the task is on today's list of the plan right now, so its slot
/// stays empty (D19). [plannedDate]: the day the plan has it on (T-907).
Future<void> toggleDone(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  required bool onPlan,
  required LocalDate? plannedDate,
  required bool isDone,
}) async {
  final actions = ref.read(taskActionsProvider);
  if (isDone) {
    await actions.uncomplete(task.id);
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  if (!await actions.complete(
    task.id,
    onPlan: onPlan,
    plannedDate: plannedDate,
  )) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.taskPausedHint)));
    return;
  }
  unawaited(HapticFeedback.lightImpact());
}

/// Asks for a new due date, today or later, and stores it.
Future<void> moveDueDate(
  BuildContext context,
  WidgetRef ref,
  Task task,
  LocalDate today,
) async {
  final actions = ref.read(taskActionsProvider);
  final picked = await showDatePicker(
    context: context,
    initialDate: dateTimeOf(today),
    firstDate: dateTimeOf(today),
    lastDate: DateTime(today.year + 10, 12, 31),
  );
  if (picked != null) {
    await actions.setDueDate(task, LocalDate.fromDateTime(picked));
  }
}

/// Moves the task to the Trash and offers "Undo". A recurring task first
/// warns that the series stops (D20, T-711); skipping one repeat is in the
/// long-press menu ([showTaskMenu]). Returns whether the task was removed
/// (false on Cancel).
Future<bool> deleteWithUndo(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  // Taken now: the snackbar may outlive the widget.
  final actions = ref.read(taskActionsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  if (task.recurrence != null) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteRecurringTitle),
        content: Text(l10n.deleteRecurringBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const ValueKey('deleteSeries'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteSeries),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }

  await actions.delete(task.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      undoSnackBar(
        message: l10n.taskMovedToTrash,
        undoLabel: l10n.actionUndo,
        onUndo: () => unawaited(actions.restore(task.id)),
      ),
    );
  return true;
}

/// "Not this time" for a recurring task (D20): to the Trash, the next repeat
/// comes; "Undo" brings it back and takes the next one away again.
Future<void> skipWithUndo(
  BuildContext context,
  WidgetRef ref,
  Task task,
) async {
  // Taken now: the snackbar may outlive the widget.
  final actions = ref.read(taskActionsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  await actions.skip(task.id);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      undoSnackBar(
        message: l10n.taskSkipped,
        undoLabel: l10n.actionUndo,
        // A restored skip takes its untouched successor away again.
        onUndo: () => unawaited(actions.restore(task.id)),
      ),
    );
}

/// What a tap on a task card offers (T-402, T-711, D22): skip this repeat of
/// a recurring task, fix it to a day, release it, move or remove the due
/// date of an overdue task (D18), or open the editor.
Future<void> showTaskMenu(
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
          if (task.recurrence != null)
            ListTile(
              key: const ValueKey('menuSkip'),
              leading: const Icon(Icons.skip_next_outlined),
              title: Text(l10n.skipThisTime),
              onTap: () => Navigator.of(context).pop('skip'),
            ),
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
          if (task.dueDate case final due? when due < today) ...[
            ListTile(
              key: const ValueKey('menuMoveDue'),
              leading: const Icon(Icons.event_outlined),
              title: Text(l10n.dueDateMove),
              onTap: () => Navigator.of(context).pop('moveDue'),
            ),
            ListTile(
              key: const ValueKey('menuClearDue'),
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(l10n.dueDateClear),
              onTap: () => Navigator.of(context).pop('clearDue'),
            ),
          ],
          ListTile(
            key: const ValueKey('menuEdit'),
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
    case 'skip':
      await skipWithUndo(context, ref, task);
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
    case 'moveDue':
      await moveDueDate(context, ref, task, today);
    case 'clearDue':
      await actions.setDueDate(task, null);
    case 'edit':
      unawaited(context.push(AppRoutes.task(task.id)));
  }
}
