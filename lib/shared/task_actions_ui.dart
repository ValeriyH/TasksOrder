import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_tile.dart';

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

/// Completes the task and offers "Undo" in a snackbar.
///
/// [onPlan]: the task is on today's list of the plan right now, so its slot
/// stays empty (D19).
Future<void> completeWithUndo(
  BuildContext context,
  WidgetRef ref,
  Task task, {
  required bool onPlan,
}) async {
  // Taken now: the snackbar may outlive the widget.
  final actions = ref.read(taskActionsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;

  await actions.complete(task.id, onPlan: onPlan);
  unawaited(HapticFeedback.lightImpact());
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      undoSnackBar(
        message: l10n.taskCompleted,
        undoLabel: l10n.actionUndo,
        onUndo: () => unawaited(actions.uncomplete(task.id)),
      ),
    );
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
