import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';

/// Turns the pile of tasks into a day-by-day plan.
///
/// A pure function: the same input gives the same plan, there is no clock
/// and no randomness. The algorithm is specified in
/// docs/04 Planner Algorithm.md.
class Planner {
  const Planner();

  /// Plans [activeTasks] from [today] over `settings.planningHorizonDays`
  /// days (today included).
  ///
  /// [overrides] are keyed by their date. [completedTodayCount] is the number
  /// of tasks completed today from today's list (see [countCompletedToday]);
  /// it lowers today's capacity so that a finished slot is not refilled (D3).
  /// Done and deleted tasks in [activeTasks] are ignored.
  Plan plan({
    required List<Task> activeTasks,
    required Settings settings,
    required Map<LocalDate, DayOverride> overrides,
    required LocalDate today,
    int completedTodayCount = 0,
  }) {
    // Focused and overdue tasks: a view over planned tasks (D17).
    final focus = <_Candidate>[];
    // Not placed yet; put in effective-priority order by each day that fills.
    final pool = <_Candidate>[];
    // Pinned tasks by the day offset they are fixed to. They wait outside
    // the pool, so neither the priority fill nor the deadline math moves them.
    final pinned = <int, List<_Candidate>>{};
    for (final task in activeTasks) {
      if (task.isDone || task.isDeleted) continue;
      final due = task.dueDate;
      final dueOffset = due == null ? null : today.daysUntil(due);
      final overdue = dueOffset != null && dueOffset < 0;
      // A missed deadline has nothing left to protect: the task is planned
      // as one without a due date and stays in Focus instead (D18).
      final candidate = _Candidate(task, overdue ? null : dueOffset);
      if (task.isFocused || overdue) focus.add(candidate);
      final pin = task.pinnedDate;
      if (pin == null) {
        pool.add(candidate);
      } else {
        // The user fixed the day; a pin in the past means today.
        final pinOffset = _atLeastZero(today.daysUntil(pin));
        (pinned[pinOffset] ??= []).add(candidate);
      }
    }
    focus.sort(_compareFocus);
    for (final sameDay in pinned.values) {
      sameDay.sort(_comparePool);
    }
    // The due-dated part of the pool, earliest deadline first.
    final dueFirst = [
      for (final c in pool)
        if (c.dueOffset != null) c,
    ]..sort(_compareDeadline);

    final resolver = CapacityResolver(settings, overrides);
    final future = _FutureCapacity(resolver, today, {
      for (final MapEntry(key: offset, value: sameDay) in pinned.entries)
        offset: sameDay.length,
    });
    final days = <PlannedDay>[];
    final atRisk = <String>[];
    var poolSorted = false;

    for (var offset = 0; offset < settings.planningHorizonDays; offset++) {
      final date = today.addDays(offset);
      final base = resolver.capacityFor(date);
      final capacity = offset == 0
          ? _atLeastZero(base - completedTodayCount)
          : base;
      // A rest day never receives tasks, not even overflow (D6). The limit
      // ignores completedTodayCount: deadline slots refill, so finishing a
      // forced task pulls in the next one that must happen today (D16).
      final hardLimit = base == 0 ? 0 : base + settings.maxOverflowPerDay;

      final picked = <_Candidate>[];
      final reasons = <PlanReason>[];
      // 1. Pinned: the user's explicit choice, so it is honoured whatever
      // the capacity, even on a rest day.
      for (final candidate in pinned.remove(offset) ?? const <_Candidate>[]) {
        picked.add(candidate);
        reasons.add(PlanReason.pinned);
      }
      if (hardLimit > 0) {
        // 2. The minimum that must happen today to keep deadlines feasible.
        // Above the hard limit the tail (latest deadlines) stays in the pool
        // and ends up at risk on a later day.
        final forced = _forcedCount(dueFirst, offset, future);
        for (var i = 0; i < forced && picked.length < hardLimit; i++) {
          picked.add(dueFirst[i]);
          reasons.add(PlanReason.deadline);
        }
        // 3. Priority fill, up to the capacity and never above it.
        if (picked.length < capacity && pool.isNotEmpty) {
          // The urgency boost depends on the day, so the order can change
          // from one day to the next; re-sort only when it did.
          final boostChanged = _applyUrgencyBoost(pool, offset, settings);
          if (boostChanged || !poolSorted) {
            pool.sort(_comparePool);
            poolSorted = true;
          }
          final taken = picked.toSet();
          for (final candidate in pool) {
            if (picked.length >= capacity) break;
            if (taken.contains(candidate)) continue;
            picked.add(candidate);
            reasons.add(PlanReason.priority);
          }
        }
      }

      final entries = <PlanEntry>[];
      for (var i = 0; i < picked.length; i++) {
        final dueOffset = picked[i].dueOffset;
        final late = dueOffset != null && offset > dueOffset;
        if (late) atRisk.add(picked[i].task.id);
        picked[i].plannedDate = date;
        entries.add(
          PlanEntry(
            taskId: picked[i].task.id,
            reason: reasons[i],
            overflow: i >= capacity,
            atRisk: late,
          ),
        );
      }
      days.add(PlannedDay(date: date, capacity: capacity, entries: entries));

      if (picked.isNotEmpty) {
        final placed = picked.toSet();
        pool.removeWhere(placed.contains);
        dueFirst.removeWhere(placed.contains);
      }
    }

    // What is left did not fit the horizon (or is pinned beyond it); list it
    // without any boost.
    for (final sameDay in pinned.values) {
      pool.addAll(sameDay);
    }
    for (final candidate in pool) {
      candidate.effectivePriority = candidate.task.priority;
    }
    pool.sort(_comparePool);

    return Plan(
      today: today,
      focus: [
        for (final candidate in focus)
          FocusEntry(
            taskId: candidate.task.id,
            focused: candidate.task.isFocused,
            overdueDays: _overdueDays(candidate.task, today),
            plannedDate: candidate.plannedDate,
          ),
      ],
      focusVisibleLimit: settings.focusVisibleLimit,
      days: days,
      laterTaskIds: [for (final c in pool) c.task.id],
      atRiskTaskIds: atRisk,
    );
  }

  /// The `completedTodayCount` for [plan]: tasks completed on the planning
  /// day [today] from that day's list (`Task.completedOnPlan`). A task done
  /// ahead of its day, from the Focus strip or the task list, held no slot
  /// of today, so today's list does not change (D19).
  ///
  /// A completion belongs to the day given by its local time and
  /// [dayStartHour] (D15). Tasks deleted after completion still count: the
  /// work was done today.
  static int countCompletedToday(
    Iterable<Task> tasks, {
    required LocalDate today,
    required int dayStartHour,
  }) {
    var count = 0;
    for (final task in tasks) {
      final completedAt = task.completedAt;
      if (completedAt == null || !task.completedOnPlan) continue;
      final day = LocalDate.todayFor(completedAt.toLocal(), dayStartHour);
      if (day == today) count++;
    }
    return count;
  }

  /// How many tasks from the head of [dueFirst] must be done on the day at
  /// [dayOffset] so that every deadline can still be met.
  ///
  /// Earliest-deadline-first is optimal for unit-size tasks: for each due
  /// date D, the tasks due by D that do not fit the capacity of the days
  /// after today up to D have to happen today.
  static int _forcedCount(
    List<_Candidate> dueFirst,
    int dayOffset,
    _FutureCapacity future,
  ) {
    final total = dueFirst.length;
    var forced = 0;
    for (var i = 0; i < total; i++) {
      final dueOffset = dueFirst[i].dueOffset!;
      // Evaluate once per distinct due date, at its last task.
      if (i + 1 < total && dueFirst[i + 1].dueOffset == dueOffset) continue;
      final need = i + 1;
      final available = future.between(dayOffset, dueOffset, enough: total);
      if (need - available > forced) forced = need - available;
      // Capacity only grows with later dates and need never exceeds total.
      if (available >= total) break;
    }
    return forced;
  }

  /// Sets every candidate's effective priority for the day at [dayOffset]
  /// (D10): a task due within `urgencySoonDays` counts one level higher,
  /// within `urgencyNearDays` two levels, never above priority 1.
  ///
  /// Returns whether any value changed.
  static bool _applyUrgencyBoost(
    List<_Candidate> pool,
    int dayOffset,
    Settings settings,
  ) {
    var changed = false;
    for (final candidate in pool) {
      final dueOffset = candidate.dueOffset;
      if (dueOffset == null) continue;
      final slack = dueOffset - dayOffset;
      final boost = slack <= settings.urgencyNearDays
          ? 2
          : slack <= settings.urgencySoonDays
          ? 1
          : 0;
      final boosted = candidate.task.priority - boost;
      final effective = boosted < 1 ? 1 : boosted;
      if (effective != candidate.effectivePriority) {
        candidate.effectivePriority = effective;
        changed = true;
      }
    }
    return changed;
  }

  static int _overdueDays(Task task, LocalDate today) {
    final due = task.dueDate;
    return due == null ? 0 : _atLeastZero(due.daysUntil(today));
  }

  /// Focus order: priority, due date (none last, so overdue tasks lead
  /// within a priority), when it was focused (overdue-only last), then age.
  static int _compareFocus(_Candidate a, _Candidate b) {
    final x = a.task;
    final y = b.task;
    var c = x.priority.compareTo(y.priority);
    if (c != 0) return c;
    c = _compareNullsLast(x.dueDate, y.dueDate);
    if (c != 0) return c;
    c = _compareNullsLast(x.focusedAt, y.focusedAt);
    if (c != 0) return c;
    return _compareAge(x, y);
  }

  /// Pool order: effective priority, original priority (a boosted task joins
  /// a tier but does not overtake that tier's own tasks), due date (none
  /// last), then age.
  static int _comparePool(_Candidate a, _Candidate b) {
    var c = a.effectivePriority.compareTo(b.effectivePriority);
    if (c != 0) return c;
    c = a.task.priority.compareTo(b.task.priority);
    if (c != 0) return c;
    c = _compareNullsLast<num>(a.dueOffset, b.dueOffset);
    if (c != 0) return c;
    return _compareAge(a.task, b.task);
  }

  /// Deadline order for candidates that all have a due date: due date,
  /// priority, then age.
  static int _compareDeadline(_Candidate a, _Candidate b) {
    var c = a.dueOffset!.compareTo(b.dueOffset!);
    if (c != 0) return c;
    c = a.task.priority.compareTo(b.task.priority);
    if (c != 0) return c;
    return _compareAge(a.task, b.task);
  }

  /// Older first; the id makes the order total, so the plan does not depend
  /// on the order of the input list.
  static int _compareAge(Task a, Task b) {
    final c = a.createdAt.compareTo(b.createdAt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  static int _compareNullsLast<T extends Comparable<T>>(T? a, T? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  static int _atLeastZero(int value) => value < 0 ? 0 : value;
}

/// A task to plan, with its due date as a day offset from today.
class _Candidate {
  _Candidate(this.task, this.dueOffset) : effectivePriority = task.priority;

  final Task task;

  /// Days from today to the due date; `null` without one and for an overdue
  /// task, whose due date no longer counts (D18). Never negative.
  final int? dueOffset;

  /// The day the task was placed on; `null` until then.
  LocalDate? plannedDate;

  /// The priority after the urgency boost for the day being filled.
  int effectivePriority;
}

/// Running totals of the base capacity (no overflow) of the days from today
/// on, extended on demand.
class _FutureCapacity {
  _FutureCapacity(this._resolver, this._today, this._pinnedOn)
    : _allZeroFrom = _findAllZeroFrom(_resolver, _today);

  final CapacityResolver _resolver;
  final LocalDate _today;

  /// Number of pinned tasks per day offset; their slots are already taken.
  final Map<int, int> _pinnedOn;

  /// When no weekday has capacity: the first offset after the last override
  /// that grants some. From there on nothing is ever added. `null` when the
  /// week has capacity.
  final int? _allZeroFrom;

  /// `_sums[k]` = capacity of the offsets `0 .. k - 1`.
  final List<int> _sums = [0];

  /// Capacity of the days after offset [after] up to and including [until].
  ///
  /// Counting stops as soon as the result reaches [enough]: the caller only
  /// needs to know that there is at least that much, and a due date decades
  /// away must not make the planner walk there day by day.
  int between(int after, int until, {required int enough}) {
    if (until <= after) return 0;
    final from = after + 1;
    while (_sums.length <= from) {
      _append();
    }
    while (_sums.length <= until + 1) {
      if (_sums.last - _sums[from] >= enough) break;
      final allZeroFrom = _allZeroFrom;
      if (allZeroFrom != null && _sums.length - 1 >= allZeroFrom) break;
      _append();
    }
    final to = until + 1 < _sums.length ? until + 1 : _sums.length - 1;
    return _sums[to] - _sums[from];
  }

  void _append() {
    final offset = _sums.length - 1;
    final free =
        _resolver.capacityFor(_today.addDays(offset)) -
        (_pinnedOn[offset] ?? 0);
    _sums.add(_sums.last + (free > 0 ? free : 0));
  }

  static int? _findAllZeroFrom(CapacityResolver resolver, LocalDate today) {
    if (resolver.settings.weeklyCapacity.any((c) => c > 0)) return null;
    var from = 0;
    for (final MapEntry(key: date, value: override)
        in resolver.overrides.entries) {
      if (override.capacity == 0) continue;
      final next = today.daysUntil(date) + 1;
      if (next > from) from = next;
    }
    return from;
  }
}
