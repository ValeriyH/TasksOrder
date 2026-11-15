import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/task_edit/repeat_sheet.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_dropdown.dart';
import 'package:tasks_order/shared/repeat_text.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';

/// Creates a task or changes the one with [taskId].
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({this.taskId, super.key});

  /// Null for a new task.
  final String? taskId;

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();

  /// The stored task; null for a new one and until it is loaded.
  Task? _original;
  late bool _loading = widget.taskId != null;
  bool _notFound = false;
  bool _saving = false;

  /// Null until the user or the loaded task says otherwise: a new task then
  /// gets Normal.
  int? _priority;
  LocalDate? _dueDate;
  LocalDate? _pinnedDate;

  /// The first day the planner may place the task on (T-714).
  LocalDate? _notBefore;

  /// The due date is before [_notBefore]: shown under the field, not saved.
  bool _dueBeforeNotBefore = false;
  bool _focused = false;

  /// How the task repeats (D20); null for an ordinary task.
  Recurrence? _recurrence;

  @override
  void initState() {
    super.initState();
    if (widget.taskId case final id?) unawaited(_load(id));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load(String id) async {
    final task = await ref.read(taskRepositoryProvider).getById(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (task == null || task.isDeleted) {
        _notFound = true;
        return;
      }
      _original = task;
      _title.text = task.title;
      _notes.text = task.notes ?? '';
      _priority = task.priority;
      _dueDate = task.dueDate;
      _pinnedDate = task.pinnedDate;
      _notBefore = task.notBefore;
      _focused = task.isFocused;
      _recurrence = task.recurrence;
    });
  }

  Future<void> _save(int priority, LocalDate today) async {
    final valid = _formKey.currentState!.validate();
    // A task due before the day it may start cannot be done (T-714).
    final notBefore = _notBefore;
    final due = _dueDate;
    setState(
      () => _dueBeforeNotBefore =
          notBefore != null && due != null && due < notBefore,
    );
    if (_saving || !valid || _dueBeforeNotBefore) return;
    setState(() => _saving = true);

    final now = ref.read(clockProvider)();
    final notes = _notes.text.trim();
    final base =
        _original ??
        Task.create(title: _title.text, priority: priority, now: now);
    var task = base
        .copyWith(
          title: _title.text.trim(),
          notes: notes.isEmpty ? null : notes,
          priority: priority,
          dueDate: _dueDate,
          pinnedDate: _pinnedDate,
          notBefore: _notBefore,
        )
        .setFocus(_focused, now);
    final rule = _recurrence;
    final original = _original;
    if (rule == null) {
      task = task.clearRecurrence(now);
    } else if (original == null ||
        rule != original.recurrence ||
        _dueDate != original.dueDate ||
        _pinnedDate != original.pinnedDate ||
        _notBefore != original.notBefore) {
      // "Start" in docs/03 Data Model.md: a new rule or new dates move the
      // schedule; a save that changed neither keeps the anchor, so a month
      // end (Jan 31 -> Feb 28) does not stick to the 28th.
      task = task.setRecurrence(rule, today: today, now: now);
    }
    await ref.read(taskRepositoryProvider).upsert(task, now);
    if (mounted) _close();
  }

  /// To the Trash with "Undo"; a recurring task asks first (T-708).
  Future<void> _delete(Task task) async {
    if (await deleteWithUndo(context, ref, task) && mounted) _close();
  }

  /// Back to where the editor was opened from; to the task list when it was
  /// opened by a link.
  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.tasks);
    }
  }

  Future<void> _pickDate({
    required LocalDate? current,
    required LocalDate today,
    required ValueChanged<LocalDate> onPicked,
  }) async {
    // No new dates in the past, but a stored one stays reachable.
    final first = current != null && current < today ? current : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime(current ?? today),
      firstDate: _dateTime(first),
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() => onPicked(LocalDate.fromDateTime(picked)));
    }
  }

  Future<void> _pickRepeat(LocalDate today) async {
    final choice = await showRepeatSheet(
      context,
      current: _recurrence,
      anchor: _pinnedDate ?? _dueDate ?? _notBefore ?? today,
    );
    if (choice != null && mounted) {
      setState(() => _recurrence = choice.rule);
    }
  }

  static DateTime _dateTime(LocalDate date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final today = ref.watch(todayProvider).value;
    final original = _original;
    final title = Text(
      widget.taskId == null ? l10n.taskNewTitle : l10n.taskEditTitle,
    );

    if (_notFound) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: Center(child: Text(l10n.taskNotFound)),
      );
    }
    if (_loading || settings == null || today == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final scale = settings.priorityScale;
    // A level the scale does not offer is kept unless the user picks another.
    final priority = _priority ?? PriorityLabels.normal;
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        // Also when the editor was opened by a link and there is no screen
        // below it.
        leading: BackButton(onPressed: _close),
        title: title,
        actions: [
          if (original != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.actionDelete,
              onPressed: () => unawaited(_delete(original)),
            ),
          TextButton(
            onPressed: _saving ? null : () => unawaited(_save(priority, today)),
            child: Text(l10n.actionSave),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    autofocus: widget.taskId == null,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.taskTitleLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n.taskTitleRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: l10n.taskNotesLabel,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PriorityDropdown(
                    scale: scale,
                    value: priority,
                    onChanged: (value) => setState(() => _priority = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DateTile(
              icon: Icons.event_outlined,
              label: l10n.taskDueDateLabel,
              value: _dueDate == null
                  ? null
                  : dates.formatFullDate(_dateTime(_dueDate!)),
              onTap: () => unawaited(
                _pickDate(
                  current: _dueDate,
                  today: today,
                  onPicked: (date) => _dueDate = date,
                ),
              ),
              onClear: () => setState(() => _dueDate = null),
            ),
            _DateTile(
              key: const ValueKey('notBefore'),
              icon: Icons.hourglass_empty,
              label: l10n.taskNotBeforeLabel,
              value: _notBefore == null
                  ? null
                  : dates.formatFullDate(_dateTime(_notBefore!)),
              hint: l10n.taskNotBeforeHint,
              error: _dueBeforeNotBefore ? l10n.taskDueBeforeNotBefore : null,
              onTap: () => unawaited(
                _pickDate(
                  current: _notBefore,
                  today: today,
                  onPicked: (date) => _notBefore = date,
                ),
              ),
              onClear: () => setState(() => _notBefore = null),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.center_focus_strong_outlined),
              title: Text(l10n.taskFocusLabel),
              subtitle: Text(l10n.taskFocusHint),
              value: _focused,
              onChanged: (value) => setState(() => _focused = value),
            ),
            _DateTile(
              icon: Icons.push_pin_outlined,
              label: l10n.taskPinDateLabel,
              value: _pinnedDate == null
                  ? null
                  : dates.formatFullDate(_dateTime(_pinnedDate!)),
              onTap: () => unawaited(
                _pickDate(
                  current: _pinnedDate,
                  today: today,
                  onPicked: (date) => _pinnedDate = date,
                ),
              ),
              onClear: () => setState(() => _pinnedDate = null),
              shortcut: _pinnedDate == today
                  ? null
                  : TextButton(
                      onPressed: () => setState(() => _pinnedDate = today),
                      child: Text(l10n.dateToday),
                    ),
            ),
            _RepeatTile(
              rule: _recurrence,
              hint: _pinnedDate != null
                  ? l10n.repeatHintPinned
                  : _dueDate != null
                  ? l10n.repeatHintDue
                  : l10n.repeatHintFree,
              onTap: () => unawaited(_pickRepeat(today)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that shows a date, opens the date picker on tap and has a button to
/// clear the date when one is set.
class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
    this.shortcut,
    this.hint,
    this.error,
    super.key,
  });

  final IconData icon;
  final String label;

  /// The formatted date; null when none is set.
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// An extra button before the clear button.
  final Widget? shortcut;

  /// What the field does, under the date.
  final String? hint;

  /// Why the date cannot be saved, in place of [hint].
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final note = error ?? hint;
    final date = value ?? l10n.dateNotSet;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: note == null
          ? Text(date)
          : Text.rich(
              TextSpan(
                text: '$date\n',
                children: [
                  TextSpan(
                    text: note,
                    style: error == null
                        ? null
                        : TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ),
            ),
      isThreeLine: note != null,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?shortcut,
          if (value != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.actionClear,
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

/// The "Repeat" row (D20, T-707): the rule in one line and where the dates
/// of the repeats go; a tap opens the repeat sheet.
class _RepeatTile extends StatelessWidget {
  const _RepeatTile({
    required this.rule,
    required this.hint,
    required this.onTap,
  });

  final Recurrence? rule;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rule = this.rule;
    return ListTile(
      key: const ValueKey('repeat'),
      leading: const Icon(Icons.repeat),
      title: Text(l10n.repeatTitle),
      subtitle: Text(
        rule == null ? l10n.repeatNever : '${repeatSummary(l10n, rule)}\n$hint',
      ),
      isThreeLine: rule != null,
      onTap: onTap,
    );
  }
}
