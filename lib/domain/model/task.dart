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
/// - [focusedAt] is set exactly when [isFocused] is true;
/// - [completedOnPlan] is true only for a done task.
///
/// Use [Task.create] and the transition methods ([complete], [setFocus],
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
    'isFocused == (focusedAt != null)',
    'focusedAt must be set exactly when isFocused is true',
  )
  @Assert(
    '!completedOnPlan || status == TaskStatus.done',
    'completedOnPlan needs a done task',
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

    /// Focus mark (D17): the task is kept in sight in the Focus view. It is
    /// planned like any other task.
    @Default(false) bool isFocused,

    /// UTC instant the mark was set; tie-breaker in the Focus view.
    DateTime? focusedAt,

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

    /// The task was on today's list when it was completed (D19). Only such
    /// completions use up the capacity of that day; false while active.
    @Default(false) bool completedOnPlan,

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
    bool isFocused = false,
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
      isFocused: isFocused,
      focusedAt: isFocused ? utc : null,
      createdAt: utc,
      updatedAt: utc,
    );
  }

  bool get isDone => status == TaskStatus.done;

  /// In the Trash (soft-deleted).
  bool get isDeleted => deletedAt != null;

  /// Whether [priority] fits the given priority [scale] (3, 5 or 10).
  bool isValidPriority(int scale) => PriorityLabels.isValid(priority, scale);

  /// Marks the task done at [now].
  ///
  /// [onPlan] tells whether the task was on today's list of the plan at that
  /// moment. The plan is not stored, so the caller has to say it: a completion
  /// from today's list leaves its slot empty, any other one (from the Focus
  /// strip, a later day, the task list) leaves today as it is (D3, D19).
  Task complete(DateTime now, {required bool onPlan}) {
    if (isDone) return this;
    final utc = now.toUtc();
    return copyWith(
      status: TaskStatus.done,
      completedAt: utc,
      completedOnPlan: onPlan,
      updatedAt: utc,
    );
  }

  /// Returns a done task to the active pool.
  Task uncomplete(DateTime now) {
    if (!isDone) return this;
    return copyWith(
      status: TaskStatus.active,
      completedAt: null,
      completedOnPlan: false,
      updatedAt: now.toUtc(),
    );
  }

  /// Sets or clears the Focus mark. Focusing an already focused task keeps
  /// its place in the Focus view.
  Task setFocus(bool value, DateTime now) {
    if (value == isFocused) return this;
    final utc = now.toUtc();
    return copyWith(
      isFocused: value,
      focusedAt: value ? utc : null,
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
