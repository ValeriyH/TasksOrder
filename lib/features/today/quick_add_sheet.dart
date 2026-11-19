import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_dropdown.dart';

/// Opens the quick-add sheet: a title, a priority and "pin to today"
/// (T-1102). The rest of a task is set in the editor, which the sheet opens
/// with what was typed.
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

  /// Null until the user picks one: then Normal.
  int? _priority;

  /// The chip "Today": the new task is pinned to today (T-1102).
  bool _pinToday = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The sheet lives in the navigator of the Today tab: another tab only
    // hides it, with its keyboard. Close it instead, as if dismissed.
    if (!TickerMode.valuesOf(context).enabled) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add(int priority, LocalDate today) async {
    if (_saving || _title.text.trim().isEmpty) return;
    _saving = true;
    await ref
        .read(taskActionsProvider)
        .add(
          title: _title.text,
          priority: priority,
          pinnedDate: _pinToday ? today : null,
        );
    unawaited(HapticFeedback.lightImpact());
    if (mounted) Navigator.of(context).pop();
  }

  /// Closes the sheet and opens the editor of a new task with what was
  /// typed; nothing is stored until the editor saves.
  void _openEditor(LocalDate today) {
    final router = GoRouter.of(context);
    final draft = TaskDraft(
      title: _title.text.trim(),
      priority: _priority,
      pinnedDate: _pinToday ? today : null,
    );
    Navigator.of(context).pop();
    unawaited(router.push(AppRoutes.taskNew, extra: draft));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final today = ref.watch(todayProvider).value;
    if (settings == null || today == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(heightFactor: 1, child: CircularProgressIndicator()),
      );
    }
    final scale = settings.priorityScale;
    final priority = _priority ?? PriorityLabels.normal;

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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              key: const ValueKey('quickAddFullEditor'),
              icon: const Icon(Icons.open_in_full),
              tooltip: l10n.quickAddFullEditor,
              onPressed: () => _openEditor(today),
            ),
          ),
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
            onSubmitted: (_) => unawaited(_add(priority, today)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.outlined(
                key: const ValueKey('quickAddPinToday'),
                isSelected: _pinToday,
                icon: const Icon(Icons.push_pin_outlined),
                selectedIcon: const Icon(Icons.push_pin),
                tooltip: l10n.quickAddPinToday,
                // A square as tall as the priority field next to it.
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () => setState(() => _pinToday = !_pinToday),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PriorityDropdown(
                  scale: scale,
                  value: priority,
                  onChanged: (value) => setState(() => _priority = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _title.text.trim().isEmpty
                ? null
                : () => unawaited(_add(priority, today)),
            child: Text(l10n.actionAdd),
          ),
        ],
      ),
    );
  }
}
