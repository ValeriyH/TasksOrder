import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_dropdown.dart';

/// Opens the quick-add sheet: a title, a priority and nothing else. The rest
/// of a task is set in the editor.
Future<void> showQuickAdd(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  // Lets the sheet move up with the keyboard.
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => const QuickAddSheet(),
);

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _title = TextEditingController();

  /// Null until the user picks one: then the middle of the scale.
  int? _priority;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add(int priority) async {
    if (_saving || _title.text.trim().isEmpty) return;
    _saving = true;
    await ref
        .read(taskActionsProvider)
        .add(title: _title.text, priority: priority);
    unawaited(HapticFeedback.lightImpact());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(heightFactor: 1, child: CircularProgressIndicator()),
      );
    }
    final scale = settings.priorityScale;
    final priority = (_priority ?? defaultPriority(scale)).clamp(1, scale);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.taskTitleLabel,
              border: const OutlineInputBorder(),
            ),
            // Enables the button with the first letter.
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_add(priority)),
          ),
          const SizedBox(height: 16),
          PriorityDropdown(
            scale: scale,
            value: priority,
            onChanged: (value) => setState(() => _priority = value),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _title.text.trim().isEmpty
                ? null
                : () => unawaited(_add(priority)),
            child: Text(l10n.actionAdd),
          ),
        ],
      ),
    );
  }
}
