import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task_size.dart';
import 'package:uuid/uuid.dart';

part 'task.freezed.dart';

/// D14: there is no "dropped" status; removal is a soft delete ([Task.deletedAt]).
enum TaskStatus { active, done }

/// A thing to do. See docs/03 Data Model.md for the field table.
///
/// Invariants, checked by assertions:
/// - [title] is not blank;
/// - [priority] is a level of the table, 1..10 (D1, ADR-17);
/// - [completedAt] is set exactly when [status] is [TaskStatus.done];
/// - [focusedAt] is set exactly when [isFocused] is true;
/// - [completedOnPlan] is true and [completedPlanDate] is set only for a
///   done task;
/// - a [recurrence] comes with a [seriesId] and an [occurrenceDate] (D20);
/// - [weight] is at least 1 (D21);
/// - [allowedWeekdays] is null or holds one to six weekdays, 0..6 (D23).
///
/// Use [Task.create] and the transition methods ([complete], [setFocus],
/// [trash], ...) instead of `copyWith` for those fields: they keep the
/// invariants and bump [updatedAt], which sync will rely on (D12).
@freezed
abstract class Task with _$Task {
  @Assert('title.trim().isNotEmpty', 'title must not be blank')
  @Assert('priority >= 1 && priority <= 10', 'priority is a level 1..10')
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
  @Assert(
    'completedPlanDate == null || status == TaskStatus.done',
    'completedPlanDate needs a done task',
  )
  @Assert(
    'recurrence == null || (seriesId != null && occurrenceDate != null)',
    'a repeat rule needs seriesId and occurrenceDate',
  )
  @Assert('weight >= 1', 'weight is at least one half-slot')
  @Assert(
    'allowedWeekdays == null || '
        '(allowedWeekdays.isNotEmpty && '
        'allowedWeekdays.length < 7 && '
        'allowedWeekdays.every((day) => day >= 0 && day <= 6))',
    'allowedWeekdays is null or one to six weekdays within 0..6',
  )
  // Not const: the title assertion calls a method.
  factory Task({
    /// UUID v4.
    required String id,
    required String title,
    String? notes,

    /// A level of the table: 1 = highest .. 10 = lowest, whatever the scale
    /// (D1, ADR-17); Normal is 5. See `PriorityLabels`.
    required int priority,

    /// Size in half-slots of the daily capacity (D21, ADR-19): 1 small,
    /// 2 normal, 4 large; any value >= 1 is valid and reads as the nearest
    /// [TaskSize]. The planner caps it by the biggest weekday (`effWeight`).
    @Default(TaskSize.defaultWeight) int weight,
    LocalDate? dueDate,

    /// Focus mark (D17): the task is kept in sight in the Focus view. It is
    /// planned like any other task.
    @Default(false) bool isFocused,

    /// UTC instant the mark was set; tie-breaker in the Focus view.
    DateTime? focusedAt,

    /// Manual "do it on this day" (v0.2).
    LocalDate? pinnedDate,

    /// Release date: the task is not planned before this day (D20; the
    /// planner honours it from T-703). Set on the successor of a recurring
    /// task; a snooze by hand may use it later.
    LocalDate? notBefore,

    /// The days of the week the task may be planned on (D23, ADR-25):
    /// 0..6, Monday = 0 as [LocalDate.weekday]; null = any day. Never empty
    /// and never all seven: [setAllowedWeekdays] stores null for both. A pin
    /// beats it. The same for every instance of a series.
    Set<int>? allowedWeekdays,
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

    /// The day the plan had the task on when it was completed (T-907, D22):
    /// the Plan keeps the done task at the end of that day until the day is
    /// past. Null while active, for a task the plan had not placed (Later)
    /// and for completions stored before schema 4.
    LocalDate? completedPlanDate,

    /// UTC; soft delete: Trash (D14) and sync tombstone (D12).
    DateTime? deletedAt,

    /// How the task repeats (D20); null for an ordinary task. The same for
    /// every instance of a series.
    Recurrence? recurrence,

    /// The id of the first task of the series; kept when the rule is
    /// cleared, so the history stays together (ADR-18).
    String? seriesId,

    /// The date of this instance in the series' schedule; a one-off move of
    /// the pin or the due date does not change it.
    LocalDate? occurrenceDate,
  }) = _Task;

  const Task._();

  /// A new active task with a fresh UUID, created at [now].
  ///
  /// The [title] is trimmed; a blank title, a [priority] outside 1..10 or a
  /// [weight] below 1 throws [ArgumentError]. Pass [id] only to get a
  /// predictable value in tests.
  factory Task.create({
    required String title,
    required int priority,
    required DateTime now,
    int weight = TaskSize.defaultWeight,
    LocalDate? dueDate,
    String? notes,
    bool isFocused = false,
    String? id,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be blank');
    }
    if (!PriorityLabels.isValid(priority)) {
      throw ArgumentError.value(priority, 'priority', 'Must be in 1..10');
    }
    if (weight < 1) {
      throw ArgumentError.value(weight, 'weight', 'Must be at least 1');
    }
    final utc = now.toUtc();
    return Task(
      id: id ?? const Uuid().v4(),
      title: trimmed,
      notes: notes,
      priority: priority,
      weight: weight,
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

  /// Marks the task done at [now].
  ///
  /// [onPlan] tells whether the task was on today's list of the plan at that
  /// moment. The plan is not stored, so the caller has to say it: a completion
  /// from today's list leaves its slot empty, any other one (from the Focus
  /// strip, a later day, the task list) leaves today as it is (D3, D19).
  ///
  /// [plannedDate] is the day the plan had the task on at that moment, null
  /// when the plan had not placed it (T-907).
  Task complete(DateTime now, {required bool onPlan, LocalDate? plannedDate}) {
    if (isDone) return this;
    final utc = now.toUtc();
    return copyWith(
      status: TaskStatus.done,
      completedAt: utc,
      completedOnPlan: onPlan,
      completedPlanDate: plannedDate,
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
      completedPlanDate: null,
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

  /// Whether the planner may place the task on [date] as far as its
  /// [allowedWeekdays] go (D23): always without the limit.
  bool allowsDay(LocalDate date) =>
      allowedWeekdays?.contains(date.weekday) ?? true;

  /// Limits the task to [days] of the week (0..6, Monday = 0), or lifts the
  /// limit: null, an empty set and all seven days mean any day and are
  /// stored as null (D23). A day outside 0..6 throws [ArgumentError].
  Task setAllowedWeekdays(Set<int>? days, DateTime now) {
    if (days != null) {
      for (final day in days) {
        if (day < 0 || day > 6) {
          throw ArgumentError.value(days, 'days', 'Weekdays are 0..6');
        }
      }
    }
    final limited = days != null && days.isNotEmpty && days.length < 7;
    final next = limited ? Set<int>.of(days) : null;
    final current = allowedWeekdays;
    final same = next == null
        ? current == null
        : current != null &&
              current.length == next.length &&
              current.containsAll(next);
    if (same) return this;
    return copyWith(allowedWeekdays: next, updatedAt: now.toUtc());
  }

  /// A fixed namespace for [successorId]: version 5 UUIDs of the app.
  static const _seriesNamespace = '6f1c2a3e-8d4b-5e7f-9a0b-1c2d3e4f5a6b';

  /// Makes the task repeat by [rule], or changes the rule ("Start" in
  /// docs/03 Data Model.md): the task starts a series when it has none
  /// ([seriesId] = its own id) and its [occurrenceDate] becomes its pin, else
  /// its due date, else its release date, else [today]. A rule by schedule is
  /// anchored on that date, whatever anchor [rule] came with. Saving the
  /// editor calls it again, so a new pin or due date moves the schedule.
  Task setRecurrence(
    Recurrence rule, {
    required LocalDate today,
    required DateTime now,
  }) {
    final occurrence = pinnedDate ?? dueDate ?? notBefore ?? today;
    final anchored = switch (rule) {
      IntervalRecurrence(afterDone: false) => Recurrence.interval(
        every: rule.every,
        unit: rule.unit,
        anchor: occurrence,
      ),
      _ => rule,
    };
    return copyWith(
      recurrence: anchored,
      seriesId: seriesId ?? id,
      occurrenceDate: occurrence,
      updatedAt: now.toUtc(),
    );
  }

  /// Stops repeating: the task stays as an ordinary task of its series.
  Task clearRecurrence(DateTime now) {
    if (recurrence == null && occurrenceDate == null) return this;
    return copyWith(
      recurrence: null,
      occurrenceDate: null,
      updatedAt: now.toUtc(),
    );
  }

  /// The id of the next instance: a version 5 UUID of this id, the same on
  /// every device (D12) and known to undo without a search (ADR-18).
  String get successorId => const Uuid().v5(_seriesNamespace, 'next/$id');

  /// The next instance of the series when this one is completed or
  /// ([skipped]) skipped on [today] (docs/03 Data Model.md, "Rules of a
  /// series").
  ///
  /// By schedule: the next date is the first date of the rule after the
  /// later of [today] and [occurrenceDate], so missed repeats are dropped
  /// and an early completion does not give a second instance for the same
  /// date. The dates follow the ones this task has: a pin moves to the next
  /// date (a due date keeps its distance from it); a due date alone moves
  /// there and the task is released the day after this occurrence; with
  /// neither the task is released on the next date.
  ///
  /// From completion (T-712): a completion counts from [today], whenever it
  /// is; a skip ("not this time") counts from the later of [today] and the
  /// date of this instance (its pin, else [occurrenceDate]), so a repeat
  /// skipped ahead does not come back on the same date. A pinned instance
  /// gives a successor pinned on the next date; otherwise it is released on
  /// that date. A due date is not carried over: when such a repeat starts is
  /// not known ahead.
  ///
  /// Throws [StateError] when the task does not repeat.
  Task successor({
    required DateTime now,
    required LocalDate today,
    bool skipped = false,
  }) {
    final rule = recurrence;
    final occurrence = occurrenceDate;
    if (rule == null || occurrence == null) {
      throw StateError('Task $id does not repeat');
    }
    final pin = pinnedDate;
    final due = dueDate;
    final own = pin ?? occurrence;
    final next = rule.isAfterDone
        ? rule.addTo(skipped && own > today ? own : today)
        : rule.firstAfter(today > occurrence ? today : occurrence);

    final LocalDate? nextPin;
    final LocalDate? nextDue;
    final LocalDate? release;
    if (rule.isAfterDone) {
      nextPin = pin == null ? null : next;
      nextDue = null;
      release = pin == null ? next : null;
    } else if (pin != null) {
      nextPin = next;
      nextDue = due == null ? null : next.addDays(pin.daysUntil(due));
      release = null;
    } else if (due != null) {
      nextPin = null;
      nextDue = next;
      release = occurrence.addDays(1);
    } else {
      nextPin = null;
      nextDue = null;
      release = next;
    }

    final utc = now.toUtc();
    return Task(
      id: successorId,
      title: title,
      notes: notes,
      priority: priority,
      // The repeats of a series carry its weight (D21).
      weight: weight,
      dueDate: nextDue,
      pinnedDate: nextPin,
      notBefore: release,
      // The repeats of a series keep its allowed days (D23).
      allowedWeekdays: allowedWeekdays,
      createdAt: utc,
      updatedAt: utc,
      recurrence: rule,
      seriesId: seriesId ?? id,
      occurrenceDate: next,
    );
  }
}
