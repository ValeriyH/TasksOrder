import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
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
    // The stored instance and the ghosts of each recurring task, in order.
    final series = <String, _Series>{};
    for (final task in activeTasks) {
      if (task.isDone || task.isDeleted) continue;
      final due = task.dueDate;
      final dueOffset = due == null ? null : today.daysUntil(due);
      final overdue = dueOffset != null && dueOffset < 0;
      // A missed deadline has nothing left to protect: the task is planned
      // as one without a due date and stays in Focus instead (D18).
      // A release date in the past or today changes nothing (T-703).
      final release = task.notBefore;
      final candidate = _Candidate(
        task,
        overdue ? null : dueOffset,
        release == null ? 0 : _atLeastZero(today.daysUntil(release)),
      );
      if (task.isFocused || overdue) focus.add(candidate);
      if (task.recurrence != null && task.occurrenceDate != null) {
        series[task.id] = _Series()..add(candidate);
      }
      final pin = task.pinnedDate;
      if (pin == null) {
        pool.add(candidate);
      } else {
        // The user fixed the day; a pin in the past means today.
        final pinOffset = _atLeastZero(today.daysUntil(pin));
        (pinned[pinOffset] ??= []).add(candidate);
      }
    }
    // 1b. Ghosts: the later repeats of recurring tasks inside the horizon
    // (D20, T-704). They take slots like real tasks, but never today, never
    // in Focus, later or the at-risk list.
    for (final ghost in _ghosts(
      activeTasks,
      today,
      settings.planningHorizonDays,
    )) {
      series[ghost.task.id]?.add(ghost);
      final pinOffset = ghost.pinOffset;
      if (pinOffset == null) {
        pool.add(ghost);
      } else {
        (pinned[pinOffset] ??= []).add(ghost);
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
        _settle(candidate, offset);
      }
      if (hardLimit > 0) {
        // 2. The minimum that must happen today to keep deadlines feasible,
        // taken from the released tasks in deadline order. Above the hard
        // limit the tail (latest deadlines) stays in the pool and ends up at
        // risk on a later day.
        var forced = _forcedCount(dueFirst, offset, future);
        for (final candidate in dueFirst) {
          if (forced == 0 || picked.length >= hardLimit) break;
          if (candidate.releaseOffset > offset) continue;
          if (!_ready(candidate, offset)) continue;
          picked.add(candidate);
          reasons.add(PlanReason.deadline);
          _settle(candidate, offset);
          forced--;
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
            // Not released yet: it waits for its day (T-703).
            if (candidate.releaseOffset > offset) continue;
            if (!_ready(candidate, offset)) continue;
            picked.add(candidate);
            reasons.add(PlanReason.priority);
            _settle(candidate, offset);
          }
        }
      }

      final entries = <PlanEntry>[];
      for (var i = 0; i < picked.length; i++) {
        final dueOffset = picked[i].dueOffset;
        final late = dueOffset != null && offset > dueOffset;
        final ghostDate = picked[i].ghostDate;
        // The at-risk list is about tasks the user can act on: a ghost keeps
        // the flag on its entry only.
        if (late && ghostDate == null) atRisk.add(picked[i].task.id);
        picked[i].plannedDate = date;
        entries.add(
          PlanEntry(
            taskId: picked[i].task.id,
            reason: reasons[i],
            overflow: i >= capacity,
            atRisk: late,
            occurrenceDate: ghostDate,
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
    // without any boost. A ghost that found no day is dropped.
    for (final sameDay in pinned.values) {
      pool.addAll(sameDay);
    }
    pool.removeWhere((candidate) => candidate.ghostDate != null);
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

  /// Whether [task] was completed on the planning day [today]: by the local
  /// time of its completion and [dayStartHour] (D15).
  static bool completedOn(Task task, LocalDate today, int dayStartHour) =>
      completionDay(task, dayStartHour) == today;

  /// The planning day [task] was completed on (D15); null while active.
  static LocalDate? completionDay(Task task, int dayStartHour) {
    final completedAt = task.completedAt;
    return completedAt == null
        ? null
        : LocalDate.todayFor(completedAt.toLocal(), dayStartHour);
  }

  /// Whether the done [task] stays on [day] of the Plan, dimmed at its end
  /// (T-907, D22): it was on that day when it was completed and the day is
  /// not past. A completion stored before schema 4 does not know its day; one
  /// from today's list (D19) stays on today, the day it was done.
  static bool keptOnDay(
    Task task,
    LocalDate day, {
    required LocalDate today,
    required int dayStartHour,
  }) {
    if (!task.isDone || task.isDeleted || day < today) return false;
    final planned = task.completedPlanDate;
    if (planned != null) return planned == day;
    return task.completedOnPlan &&
        day == today &&
        completedOn(task, today, dayStartHour);
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

  /// The active tasks that cannot be completed until the next day (T-710):
  /// their rule counts from completion and another task of their series was
  /// completed on the planning day [today]. A second completion on the same
  /// day would bring the same next date again, so it is always a slip.
  /// Rules by the calendar are not paused: doing the next one ahead (a rent
  /// paid for two months) is real.
  ///
  /// A completion belongs to the day given by its local time and
  /// [dayStartHour] (D15).
  static Set<String> pausedToday(
    Iterable<Task> tasks, {
    required LocalDate today,
    required int dayStartHour,
  }) {
    final doneToday = <String>{};
    for (final task in tasks) {
      final completedAt = task.completedAt;
      final series = task.seriesId;
      if (completedAt == null || series == null) continue;
      final day = LocalDate.todayFor(completedAt.toLocal(), dayStartHour);
      if (day == today) doneToday.add(series);
    }
    if (doneToday.isEmpty) return const {};
    return {
      for (final task in tasks)
        if (!task.isDone &&
            (task.recurrence?.isAfterDone ?? false) &&
            doneToday.contains(task.seriesId))
          task.id,
    };
  }

  /// How many released tasks of [dueFirst] must be done on the day at
  /// [dayOffset] so that every deadline can still be met.
  ///
  /// Earliest-deadline-first is optimal for unit-size tasks: for each due
  /// date D, the tasks due by D that do not fit the capacity of the days
  /// after today up to D have to happen today. Tasks not released yet count
  /// in that need (they will take a slot before their due date), but only
  /// released ones can be done today, so the result for D is cut to the
  /// released tasks due by D (T-703, docs/04 "With release dates").
  static int _forcedCount(
    List<_Candidate> dueFirst,
    int dayOffset,
    _FutureCapacity future,
  ) {
    final total = dueFirst.length;
    var forced = 0;
    var released = 0;
    for (var i = 0; i < total; i++) {
      if (dueFirst[i].releaseOffset <= dayOffset) released++;
      final dueOffset = dueFirst[i].dueOffset!;
      // Evaluate once per distinct due date, at its last task.
      if (i + 1 < total && dueFirst[i + 1].dueOffset == dueOffset) continue;
      final need = i + 1;
      final available = future.between(dayOffset, dueOffset, enough: total);
      final short = need - available;
      final now = short < released ? short : released;
      if (now > forced) forced = now;
      // Capacity only grows with later dates and need never exceeds total.
      if (available >= total) break;
    }
    return forced;
  }

  /// Sets every candidate's effective priority for the day at [dayOffset]
  /// (D10): a task due within `urgencySoonDays` counts one level of the
  /// scale higher, within `urgencyNearDays` two levels, never above the first
  /// level of the scale (`PriorityLabels.raise`).
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
      final effective = PriorityLabels.raise(
        candidate.task.priority,
        boost,
        settings.priorityScale,
      );
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

  /// Order of a plain task list: the pool order without the urgency boost.
  /// Priority, then due date (none and overdue last, as the planner treats
  /// an overdue task as one without a date, D18), then age.
  static int compareForList(Task a, Task b, {required LocalDate today}) {
    num? dueOffset(Task task) {
      final due = task.dueDate;
      return due == null || due < today ? null : today.daysUntil(due);
    }

    var c = a.priority.compareTo(b.priority);
    if (c != 0) return c;
    c = _compareNullsLast<num>(dueOffset(a), dueOffset(b));
    if (c != 0) return c;
    return _compareAge(a, b);
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
    c = _compareAge(a.task, b.task);
    return c != 0 ? c : _compareRepeat(a, b);
  }

  /// Deadline order for candidates that all have a due date: due date,
  /// priority, then age.
  static int _compareDeadline(_Candidate a, _Candidate b) {
    var c = a.dueOffset!.compareTo(b.dueOffset!);
    if (c != 0) return c;
    c = a.task.priority.compareTo(b.task.priority);
    if (c != 0) return c;
    c = _compareAge(a.task, b.task);
    return c != 0 ? c : _compareRepeat(a, b);
  }

  /// Repeats of one series: the stored task first, then the ghosts by date.
  static int _compareRepeat(_Candidate a, _Candidate b) {
    final x = a.ghostDate;
    final y = b.ghostDate;
    if (x == null) return y == null ? 0 : -1;
    if (y == null) return 1;
    return x.compareTo(y);
  }

  /// The ghosts of the recurring tasks in [tasks]: one per date of the rule
  /// after `max(today, occurrenceDate)` up to the last day of the horizon.
  /// Their dates follow the ones the stored task has, as for the successor
  /// (docs/03 Data Model.md): a pin moves to the date (a due date keeps its
  /// distance), a due date alone moves there with a release on the day
  /// after the previous repeat, with neither the ghost is released on its
  /// date.
  static Iterable<_Candidate> _ghosts(
    List<Task> tasks,
    LocalDate today,
    int horizon,
  ) sync* {
    final last = today.addDays(horizon - 1);
    for (final task in tasks) {
      final rule = task.recurrence;
      final occurrence = task.occurrenceDate;
      if (rule == null || occurrence == null) continue;
      if (task.isDone || task.isDeleted) continue;
      final pin = task.pinnedDate;
      final due = task.dueDate;
      final dueFromPin = pin != null && due != null ? pin.daysUntil(due) : null;
      var previous = occurrence > today ? occurrence : today;
      for (final date in rule.datesAfter(previous, last)) {
        final offset = today.daysUntil(date);
        if (pin != null) {
          yield _Candidate(
            task,
            dueFromPin == null ? null : offset + dueFromPin,
            offset,
            ghostDate: date,
            pinOffset: offset,
          );
        } else if (due != null) {
          yield _Candidate(
            task,
            offset,
            today.daysUntil(previous) + 1,
            ghostDate: date,
          );
        } else {
          // Without dates of its own a repeat is gone once the next one is
          // due: by schedule the missed repeats are dropped, from completion
          // the next one counts from the day it is done.
          yield _Candidate(
            task,
            null,
            offset,
            ghostDate: date,
            expiresOffset: today.daysUntil(rule.firstAfter(date)) - 1,
          );
        }
        previous = date;
      }
    }
  }

  /// Whether [candidate] may be placed on the day at [offset] as far as its
  /// series goes (T-709): every earlier member is placed on an earlier day
  /// or has expired. So two repeats of a series never share a day and a
  /// ghost never comes before the task it repeats. Not a recurring task:
  /// always.
  static bool _ready(_Candidate candidate, int offset) {
    final series = candidate.series;
    if (series == null) return true;
    final last = series.lastPlaced;
    if (last != null && last >= offset) return false;
    final members = series.members;
    while (series.next < members.length) {
      final expires = members[series.next].expiresOffset;
      if (expires == null || offset <= expires) break;
      series.next++;
    }
    return series.next < members.length &&
        identical(members[series.next], candidate);
  }

  /// Records that [candidate] was placed on the day at [offset].
  static void _settle(_Candidate candidate, int offset) {
    final series = candidate.series;
    if (series == null) return;
    series.lastPlaced = offset;
    if (candidate.seriesIndex >= series.next) {
      series.next = candidate.seriesIndex + 1;
    }
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
  _Candidate(
    this.task,
    this.dueOffset,
    this.releaseOffset, {
    this.ghostDate,
    this.pinOffset,
    this.expiresOffset,
  }) : effectivePriority = task.priority;

  /// For a ghost without dates of its own: the last day offset it may be
  /// placed on, the day before the next date of the rule.
  final int? expiresOffset;

  /// The series of a recurring task and this candidate's place in it.
  _Series? series;
  int seriesIndex = 0;

  final Task task;

  /// Days from today to the due date; `null` without one and for an overdue
  /// task, whose due date no longer counts (D18). Never negative.
  final int? dueOffset;

  /// Days from today to the release date (`Task.notBefore`); 0 when there is
  /// none or it is not in the future. The task is planned from that day on.
  final int releaseOffset;

  /// For a ghost: the date of the repeat it stands for (T-704); null for a
  /// stored task.
  final LocalDate? ghostDate;

  /// For a pinned ghost: the day offset it is pinned to.
  final int? pinOffset;

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

/// The stored instance of a recurring task and its ghosts in date order,
/// with how far the day loop has got through them (T-709).
class _Series {
  final members = <_Candidate>[];

  /// Index of the first member that is neither placed nor expired.
  int next = 0;

  /// Day offset of the last placed member.
  int? lastPlaced;

  void add(_Candidate candidate) {
    candidate
      ..series = this
      ..seriesIndex = members.length;
    members.add(candidate);
  }
}
