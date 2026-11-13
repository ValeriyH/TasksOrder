import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:uuid/uuid.dart';

part 'task.freezed.dart';

/// D14: there is no "dropped" status; removal is a soft delete ([Task.deletedAt]).
enum TaskStatus { active, done }

/// A thing to do. See docs/03 Data Model.md for the field table.
///
/// Invariants, checked by assertions:
/// - [title] is not blank;
/// - [priority] is at least 1 (the upper bound depends on the current scale,
///   see [isValidPriority]);
/// - [completedAt] is set exactly when [status] is [TaskStatus.done];
/// - [todayFlaggedAt] is set exactly when [isToday] is true.
///
/// Use [Task.create] and the transition methods ([complete], [setToday],
/// [trash], ...) instead of `copyWith` for those fields: they keep the
/// invariants and bump [updatedAt], which sync will rely on (D12).
@freezed
abstract class Task with _$Task {
  @Assert('title.trim().isNotEmpty', 'title must not be blank')
  @Assert('priority >= 1', 'priority starts at 1')
  @Assert(
    '(status == TaskStatus.done) == (completedAt != null)',
    'completedAt must be set exactly when the task is done',
  )
  @Assert(
    'isToday == (todayFlaggedAt != null)',
    'todayFlaggedAt must be set exactly when isToday is true',
  )
  // Not const: the title assertion calls a method.
  factory Task({
    /// UUID v4.
    required String id,
    required String title,
    String? notes,

    /// 1 = highest .. `Settings.priorityScale` = lowest (D1).
    required int priority,
    LocalDate? dueDate,

    /// Today flag (D11): the task sits in the Today queue, outside capacity.
    @Default(false) bool isToday,

    /// UTC instant the flag was set; tie-breaker in the Today queue.
    DateTime? todayFlaggedAt,

    /// Manual "do it on this day" (v0.2).
    LocalDate? pinnedDate,

    /// Reserved for snooze; the planner ignores it in the MVP.
    LocalDate? notBefore,
    @Default(TaskStatus.active) TaskStatus status,

    /// UTC; planner tie-breaker, older first.
    required DateTime createdAt,

    /// UTC; bumped by every change.
    required DateTime updatedAt,

    /// UTC.
    DateTime? completedAt,

    /// UTC; soft delete: Trash (D14) and sync tombstone (D12).
    DateTime? deletedAt,
  }) = _Task;

  const Task._();

  /// A new active task with a fresh UUID, created at [now].
  ///
  /// The [title] is trimmed; a blank title or a [priority] below 1 throws
  /// [ArgumentError]. Pass [id] only to get a predictable value in tests.
  factory Task.create({
    required String title,
    required int priority,
    required DateTime now,
    LocalDate? dueDate,
    String? notes,
    bool isToday = false,
    String? id,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be blank');
    }
    if (priority < 1) {
      throw ArgumentError.value(priority, 'priority', 'Must be at least 1');
    }
    final utc = now.toUtc();
    return Task(
      id: id ?? const Uuid().v4(),
      title: trimmed,
      notes: notes,
      priority: priority,
      dueDate: dueDate,
      isToday: isToday,
      todayFlaggedAt: isToday ? utc : null,
      createdAt: utc,
      updatedAt: utc,
    );
  }

  bool get isDone => status == TaskStatus.done;

  /// In the Trash (soft-deleted).
  bool get isDeleted => deletedAt != null;

  /// Whether [priority] fits the given priority [scale] (3, 5 or 10).
  bool isValidPriority(int scale) => PriorityLabels.isValid(priority, scale);

  /// Marks the task done at [now]. The Today flag is kept, so the planner can
  /// tell flagged completions from planned ones (D3, D11).
  Task complete(DateTime now) {
    if (isDone) return this;
    final utc = now.toUtc();
    return copyWith(status: TaskStatus.done, completedAt: utc, updatedAt: utc);
  }

  /// Returns a done task to the active pool.
  Task uncomplete(DateTime now) {
    if (!isDone) return this;
    return copyWith(
      status: TaskStatus.active,
      completedAt: null,
      updatedAt: now.toUtc(),
    );
  }

  /// Sets or clears the Today flag. Re-flagging an already flagged task keeps
  /// its place in the queue.
  Task setToday(bool value, DateTime now) {
    if (value == isToday) return this;
    final utc = now.toUtc();
    return copyWith(
      isToday: value,
      todayFlaggedAt: value ? utc : null,
      updatedAt: utc,
    );
  }

  /// Soft delete: moves the task to the Trash.
  Task trash(DateTime now) {
    if (isDeleted) return this;
    final utc = now.toUtc();
    return copyWith(deletedAt: utc, updatedAt: utc);
  }

  /// Takes the task back out of the Trash.
  Task restore(DateTime now) {
    if (!isDeleted) return this;
    return copyWith(deletedAt: null, updatedAt: now.toUtc());
  }
}
