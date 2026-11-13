import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/task_tile.dart';

/// Deleted tasks, the latest first: restore one or remove it for good. What
/// stays longer than [TaskActions.trashRetention] is removed when the app
/// starts (D14).
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final trash = ref.watch(trashProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trashTitle)),
      body: switch (trash) {
        AsyncValue(:final value?) when value.isEmpty => Center(
          child: Text(l10n.trashEmpty, style: theme.textTheme.titleMedium),
        ),
        AsyncValue(:final value?) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                l10n.trashHint(TaskActions.trashRetention.inDays),
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final task in value) _TrashTile(task: task),
          ],
        ),
        AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _TrashTile extends ConsumerWidget {
  const _TrashTile({required this.task});

  final Task task;

  Future<void> _deleteForever(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final actions = ref.read(taskActionsProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.trashDeleteConfirm(task.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.trashDeleteForever),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await actions.deleteForever(task.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final deletedOn = LocalDate.fromDateTime(task.deletedAt!.toLocal());

    return ListTile(
      key: ValueKey(task.id),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.trashDeletedOn(shortDate(context, deletedOn))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore_from_trash_outlined),
            tooltip: l10n.actionRestore,
            onPressed: () =>
                unawaited(ref.read(taskActionsProvider).restore(task.id)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: l10n.trashDeleteForever,
            onPressed: () => unawaited(_deleteForever(context, ref)),
          ),
        ],
      ),
    );
  }
}
