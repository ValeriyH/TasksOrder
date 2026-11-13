import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_dropdown.dart';

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
  /// gets the middle of the scale.
  int? _priority;
  LocalDate? _dueDate;
  LocalDate? _pinnedDate;
  bool _focused = false;

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
      _focused = task.isFocused;
    });
  }

  Future<void> _save(int priority) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final now = ref.read(clockProvider)();
    final notes = _notes.text.trim();
    final base =
        _original ??
        Task.create(title: _title.text, priority: priority, now: now);
    final task = base
        .copyWith(
          title: _title.text.trim(),
          notes: notes.isEmpty ? null : notes,
          priority: priority,
          dueDate: _dueDate,
          pinnedDate: _pinnedDate,
        )
        .setFocus(_focused, now);
    await ref.read(taskRepositoryProvider).upsert(task, now);
    if (mounted) _close();
  }

  Future<void> _delete(String id) async {
    // Taken now: the snackbar outlives this screen.
    final repository = ref.read(taskRepositoryProvider);
    final clock = ref.read(clockProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    await repository.delete(id, clock());
    if (!mounted) return;
    _close();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.taskMovedToTrash),
          action: SnackBarAction(
            label: l10n.actionUndo,
            onPressed: () => unawaited(repository.restore(id, clock())),
          ),
        ),
      );
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
    // A value above the scale (the scale was made smaller) shows as the last
    // level and is stored as such on save.
    final priority = (_priority ?? defaultPriority(scale)).clamp(1, scale);
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
              onPressed: () => unawaited(_delete(original.id)),
            ),
          TextButton(
            onPressed: _saving ? null : () => unawaited(_save(priority)),
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
  });

  final IconData icon;
  final String label;

  /// The formatted date; null when none is set.
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// An extra button before the clear button.
  final Widget? shortcut;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value ?? l10n.dateNotSet),
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
