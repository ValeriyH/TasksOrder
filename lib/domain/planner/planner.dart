import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/model/task_size.dart';
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
  /// [overrides] are keyed by their date. [completedTodayWeight] is the
  /// weight in half-slots of the tasks completed today from today's list (see
  /// [completedTodayWeightOf]); it lowers today's capacity so that a finished
  /// slot is not refilled (D3, D21). Done and deleted tasks in [activeTasks]
  /// are ignored.
  ///
  /// Capacities are counted in half-slots (D21): a day of capacity `c` holds
  /// `2 × c`, a task weighs its [effWeight].
  ///
  /// A task limited to some days of the week (`Task.allowedWeekdays`, D23) is
  /// placed only on such a day, unless it is pinned.
  Plan plan({
    required List<Task> activeTasks,
    required Settings settings,
    required Map<LocalDate, DayOverride> overrides,
    required LocalDate today,
    int completedTodayWeight = 0,
  }) {
    final maxWeight = _maxWeight(settings);
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
        weight: _weightOf(task, settings, maxWeight),
      );
      if (task.isFocused || overdue) focus.add(candidate);
      if (task.recurrence != null && task.occurrenceDate != null) {
        series[task.id] = _Series()..add(candidate);
      }
      final pin = task.pinnedDate;
      if (pin == null) {
        pool.add(candidate);
      } else {
        // The user fixed the day; a pin in the past means today, or the
        // nearest allowed day of a task limited to some weekdays (D23).
        final pinOffset = pin < today
            ? _firstAllowedOffset(task, today)
            : today.daysUntil(pin);
        (pinned[pinOffset] ??= []).add(candidate);
      }
    }
    // 1b. Ghosts: the later repeats of recurring tasks inside the horizon
    // (D20, T-704). They take slots like real tasks, but never today, never
    // in Focus, later or the at-risk list.
    for (final ghost in _ghosts(activeTasks, today, settings, maxWeight)) {
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
    // Pinned weight per day: those half-slots are already taken.
    final future = _FutureCapacity(resolver, today, {
      for (final MapEntry(key: offset, value: sameDay) in pinned.entries)
        offset: sameDay.fold(0, (sum, c) => sum + c.weight),
    });
    // The weights above normal the due tasks have: each gets the check of
    // "a heavy task counts only the days it fits" (D21).
    final heavyWeights = {
      for (final c in dueFirst)
        if (c.weight > TaskSize.defaultWeight) c.weight,
    }.toList()..sort();
    // The sets of allowed weekdays the due tasks have: each gets the check
    // of "a task counts only the days it may take" (D23).
    final dueMasks = {
      for (final c in dueFirst)
        if (c.dayMask != _anyDay) c.dayMask,
    }.toList()..sort();
    // The heaviest task that is not pinned: only a day too small for it can
    // see the top-level overflow.
    final heaviest = pool.fold(0, (w, c) => c.weight > w ? c.weight : w);
    final days = <PlannedDay>[];
    final atRisk = <String>[];
    var poolSorted = false;

    for (var offset = 0; offset < settings.planningHorizonDays; offset++) {
      final date = today.addDays(offset);
      final weekday = date.weekday;
      final base = resolver.capacityFor(date);
      // In half-slots (D21).
      final room = offset == 0
          ? _atLeastZero(2 * base - completedTodayWeight)
          : 2 * base;
      // A rest day never receives tasks, not even overflow (D6). The limit
      // ignores the completed weight: deadline slots refill, so finishing a
      // forced task pulls in the next one that must happen today (D16).
      final hardRoom = base == 0 ? 0 : 2 * (base + settings.maxOverflowPerDay);

      final picked = <_Candidate>[];
      final reasons = <PlanReason>[];
      var load = 0;
      void place(_Candidate candidate, PlanReason reason) {
        picked.add(candidate);
        reasons.add(reason);
        load += candidate.weight;
        _settle(candidate, offset);
      }

      // 1. Pinned: the user's explicit choice, so it is honoured whatever
      // the capacity, even on a rest day.
      for (final candidate in pinned.remove(offset) ?? const <_Candidate>[]) {
        place(candidate, PlanReason.pinned);
      }
      if (hardRoom > 0) {
        // 2. The minimum weight that must happen today to keep deadlines
        // feasible, taken from the released tasks in deadline order: the
        // check over every due task, for each heavy weight the check over
        // the tasks that heavy, counting only the days that can hold them
        // (D21), and for each set of allowed weekdays the check over the
        // tasks that can only use those days, counting only them (D23). A
        // task that would pass the hard limit stays in the
        // pool and ends up at risk on a later day; a lighter one behind it
        // may still be taken.
        _force(
          dueFirst,
          offset,
          weekday,
          future,
          heavyWeights,
          dueMasks,
          fits: (candidate) =>
              candidate.releaseOffset <= offset &&
              _allowed(candidate, weekday) &&
              load + candidate.weight <= hardRoom &&
              _ready(candidate, offset),
          place: (candidate) => place(candidate, PlanReason.deadline),
        );
        // No task can be too heavy for a day that holds the heaviest one.
        final overflowPossible = heaviest > 2 * base;
        if (pool.isNotEmpty && (load < room || overflowPossible)) {
          // The urgency boost depends on the day, so the order can change
          // from one day to the next; re-sort only when it did.
          final boostChanged = _applyUrgencyBoost(pool, offset, settings);
          if (boostChanged || !poolSorted) {
            pool.sort(_comparePool);
            poolSorted = true;
          }
        }
        final taken = picked.toSet();
        // 2b. Top-level overflow (D21): the first task of the queue, of level
        // 1 or 2 by its own priority, that does not fit the day at all takes
        // it above the capacity, inside the hard limit; one a day.
        for (final candidate
            in overflowPossible ? pool : const <_Candidate>[]) {
          if (taken.contains(candidate)) continue;
          if (candidate.releaseOffset > offset) continue;
          if (!_allowed(candidate, weekday)) continue;
          if (!_ready(candidate, offset)) continue;
          final done = offset == 0 ? completedTodayWeight : 0;
          if (candidate.task.priority <= _overflowLevel &&
              candidate.weight > 2 * base &&
              done + load + candidate.weight <= hardRoom) {
            place(candidate, PlanReason.priority);
            taken.add(candidate);
          }
          break;
        }
        // 3. Priority fill, up to the capacity and never above it: first fit
        // in pool order (D21), so a task too heavy for what is left waits
        // and lighter ones behind it go ahead.
        if (load < room && pool.isNotEmpty) {
          for (final candidate in pool) {
            if (load >= room) break;
            if (taken.contains(candidate)) continue;
            // Not released yet: it waits for its day (T-703).
            if (candidate.releaseOffset > offset) continue;
            // Not a day of its week (D23): it waits for one, and that is
            // not "waits for room".
            if (!_allowed(candidate, weekday)) continue;
            if (!_ready(candidate, offset)) continue;
            if (load + candidate.weight > room) {
              candidate.waitsForRoom = true;
              continue;
            }
            place(candidate, PlanReason.priority);
          }
        }
      }

      final entries = <PlanEntry>[];
      var before = 0;
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
            // Above the room of the day, wholly or in part.
            overflow: before + picked[i].weight > room,
            atRisk: late,
            occurrenceDate: ghostDate,
            weight: picked[i].weight,
            waitsForRoom: picked[i].waitsForRoom,
          ),
        );
        before += picked[i].weight;
      }
      days.add(
        PlannedDay(
          date: date,
          capacity: room ~/ 2,
          capacityWeight: room,
          entries: entries,
        ),
      );

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

  /// The weight of [task] the planner counts, in half-slots (D21, ADR-19):
  /// never more than the biggest weekday of [settings] holds, so every task
  /// fits some working day. Day overrides do not count.
  ///
  /// A task limited to some days of the week (D23) is capped by the biggest
  /// of those weekdays instead, so it fits one of its own days.
  static int effWeight(Task task, Settings settings) =>
      _weightOf(task, settings, _maxWeight(settings));

  /// [effWeight] with the cap of the whole week, [maxWeight], at hand.
  static int _weightOf(Task task, Settings settings, int maxWeight) {
    final days = task.allowedWeekdays;
    if (days == null) return _capped(task.weight, maxWeight);
    var biggest = 0;
    for (final day in days) {
      final capacity = settings.weeklyCapacity[day];
      if (capacity > biggest) biggest = capacity;
    }
    return _capped(task.weight, biggest > 0 ? 2 * biggest : 2);
  }

  /// The `completedTodayWeight` for [plan]: the [effWeight] of the tasks
  /// completed on the planning day [today] from that day's list (D3, D19,
  /// D21); the same tasks as [countCompletedToday].
  static int completedTodayWeightOf(
    Iterable<Task> tasks, {
    required LocalDate today,
    required Settings settings,
  }) {
    final maxWeight = _maxWeight(settings);
    var weight = 0;
    for (final task in tasks) {
      final completedAt = task.completedAt;
      if (completedAt == null || !task.completedOnPlan) continue;
      final day = LocalDate.todayFor(
        completedAt.toLocal(),
        settings.dayStartHour,
      );
      if (day == today) weight += _weightOf(task, settings, maxWeight);
    }
    return weight;
  }

  /// The cap of [effWeight]: two half-slots per slot of the biggest weekday;
  /// a week of rest days only (capacity from day overrides) caps at normal.
  static int _maxWeight(Settings settings) {
    final biggest = settings.maxWeeklyCapacity;
    return biggest > 0 ? 2 * biggest : 2;
  }

  static int _capped(int weight, int maxWeight) =>
      weight < maxWeight ? weight : maxWeight;

  /// The number of tasks completed on the planning day [today] from that
  /// day's list (`Task.completedOnPlan`), for the "done of total" of the UI. A task done
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

  /// Levels that may take a day above its capacity with a task too heavy
  /// for it (D21): Catastrophic and Critical, by their own priority.
  static const _overflowLevel = 2;

  /// Places the deadline-forced tasks of the day at [dayOffset], a
  /// [weekday] (D21, D23). Several checks say how much weight must be done
  /// that day so that every deadline can still be met ([_forcedWeight]):
  /// - over all of [dueFirst], counting every day;
  /// - for each of [heavyWeights] `w`, over the tasks of weight `w` or more,
  ///   counting only the days that can hold `w`;
  /// - for each of [dueMasks] `S` (a set of allowed weekdays), over the tasks
  ///   that can only use days of `S`, counting only those days, and the same
  ///   per heavy weight inside the set.
  ///
  /// One pass in deadline order takes a task while one of the checks it
  /// belongs to still needs weight and it [fits] (released, on an allowed
  /// day, ready in its series, inside the hard limit); a task that does not
  /// fit is skipped and the next one tried. What is taken lowers every check
  /// the task belongs to: a task done today needs no room later.
  static void _force(
    List<_Candidate> dueFirst,
    int dayOffset,
    int weekday,
    _FutureCapacity future,
    List<int> heavyWeights,
    List<int> dueMasks, {
    required bool Function(_Candidate) fits,
    required void Function(_Candidate) place,
  }) {
    if (dueFirst.isEmpty) return;
    final checks = <_ForceCheck>[];
    void add(int mask, int minWeight) {
      final check = _ForceCheck(mask, minWeight);
      final members = mask == _anyDay && minWeight == 0
          ? dueFirst
          : [
              for (final c in dueFirst)
                if (check.has(c)) c,
            ];
      check.left = _forcedWeight(
        members,
        dayOffset,
        weekday,
        future,
        minWeight,
        mask,
      );
      if (check.left > 0) checks.add(check);
    }

    add(_anyDay, 0);
    for (final w in heavyWeights) {
      add(_anyDay, w);
    }
    for (final mask in dueMasks) {
      add(mask, 0);
      for (final w in heavyWeights) {
        add(mask, w);
      }
    }
    if (checks.isEmpty) return;
    for (final candidate in dueFirst) {
      var wanted = false;
      var needsMore = false;
      for (final check in checks) {
        if (check.left <= 0) continue;
        needsMore = true;
        if (check.has(candidate)) {
          wanted = true;
          break;
        }
      }
      if (!needsMore) break;
      if (!wanted || !fits(candidate)) continue;
      place(candidate);
      for (final check in checks) {
        if (check.has(candidate)) check.left -= candidate.weight;
      }
    }
  }

  /// The weight of the tasks of [due] (in deadline order) that must be done
  /// on the day at [dayOffset], a [weekday], so that every deadline can
  /// still be met, in half-slots.
  ///
  /// For each due date D, the weight due by D that does not fit the free
  /// room of the days after today up to D has to happen today: exact for
  /// tasks of one size (earliest deadline first), a heuristic for mixed ones
  /// (D21). Only days with at least [minFree] free half-slots count, so a
  /// heavy task does not count on days too small for it, and only the
  /// weekdays of [mask], so tasks limited to some days of the week do not
  /// count on the others (D23). Tasks that cannot be done today (not
  /// released yet, or today is not one of their days) count in that need:
  /// they will take room before their due date. But only the others can be
  /// pulled into today, so the result for D is cut to their weight due by D
  /// (T-703, docs/04 "With release dates").
  static int _forcedWeight(
    List<_Candidate> due,
    int dayOffset,
    int weekday,
    _FutureCapacity future,
    int minFree,
    int mask,
  ) {
    final count = due.length;
    if (count == 0) return 0;
    final total = due.fold(0, (sum, c) => sum + c.weight);
    var forced = 0;
    var need = 0;
    var pullable = 0;
    for (var i = 0; i < count; i++) {
      need += due[i].weight;
      if (due[i].releaseOffset <= dayOffset && _allowed(due[i], weekday)) {
        pullable += due[i].weight;
      }
      final dueOffset = due[i].dueOffset!;
      // Evaluate once per distinct due date, at its last task.
      if (i + 1 < count && due[i + 1].dueOffset == dueOffset) continue;
      final available = future.between(
        dayOffset,
        dueOffset,
        enough: total,
        minFree: minFree,
        mask: mask,
      );
      final short = need - available;
      final now = short < pullable ? short : pullable;
      if (now > forced) forced = now;
      // Room only grows with later dates and need never exceeds total.
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

  /// The ghosts of the recurring tasks in [tasks] whose rule is by the
  /// calendar (a rule from completion has none, T-712): one per date of the
  /// rule after `max(today, occurrenceDate)` up to the last day of the
  /// horizon.
  /// Their dates follow the ones the stored task has, as for the successor
  /// (docs/03 Data Model.md): a pin moves to the date (a due date keeps its
  /// distance), a due date alone moves there with a release on the day
  /// after the previous repeat, with neither the ghost is released on its
  /// date.
  static Iterable<_Candidate> _ghosts(
    List<Task> tasks,
    LocalDate today,
    Settings settings,
    int maxWeight,
  ) sync* {
    final last = today.addDays(settings.planningHorizonDays - 1);
    for (final task in tasks) {
      final rule = task.recurrence;
      final occurrence = task.occurrenceDate;
      if (rule == null || occurrence == null) continue;
      if (task.isDone || task.isDeleted) continue;
      // A rule from completion has no ghosts (T-712): its dates depend on
      // when each repeat is done, so they cannot be known ahead.
      if (rule.isAfterDone) continue;
      final pin = task.pinnedDate;
      final due = task.dueDate;
      final dueFromPin = pin != null && due != null ? pin.daysUntil(due) : null;
      // Ghosts carry the weight of their task (D21).
      final weight = _weightOf(task, settings, maxWeight);
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
            weight: weight,
          );
        } else if (due != null) {
          yield _Candidate(
            task,
            offset,
            today.daysUntil(previous) + 1,
            ghostDate: date,
            weight: weight,
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
            weight: weight,
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

  /// Whether [candidate] may be placed on a day of the week [weekday] as far
  /// as the allowed days of its task go (D23, ADR-25). A ghost follows its
  /// task; a pinned candidate is never asked.
  static bool _allowed(_Candidate candidate, int weekday) =>
      (candidate.dayMask >> weekday) & 1 == 1;

  /// The day offset a pin in the past stands for (D23): today, or for a task
  /// limited to some weekdays the first allowed day from today on.
  static int _firstAllowedOffset(Task task, LocalDate today) {
    if (task.allowedWeekdays == null) return 0;
    for (var offset = 0; offset < 7; offset++) {
      if (task.allowsDay(today.addDays(offset))) return offset;
    }
    return 0;
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
    required this.weight,
    this.ghostDate,
    this.pinOffset,
    this.expiresOffset,
  }) : effectivePriority = task.priority,
       dayMask = _maskOf(task.allowedWeekdays);

  /// The allowed weekdays of the task as bits, Monday = bit 0 (D23);
  /// [_anyDay] without the limit.
  final int dayMask;

  /// The [Planner.effWeight] of the task, in half-slots (D21).
  final int weight;

  /// Skipped by the priority fill of an earlier day only because it did not
  /// fit what was left of it (D21).
  bool waitsForRoom = false;

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

/// Every weekday as bits: the [_Candidate.dayMask] of a task that may be
/// planned on any day.
const _anyDay = 0x7f;

/// A set of weekdays (Monday = 0) as bits; [_anyDay] for no set.
int _maskOf(Set<int>? weekdays) {
  if (weekdays == null) return _anyDay;
  var mask = 0;
  for (final day in weekdays) {
    mask |= 1 << day;
  }
  return mask;
}

/// One feasibility check of [Planner._force]: the due tasks that can only
/// use the weekdays of [mask] ([_anyDay]: every due task) and weigh at least
/// [minWeight], with the weight that still has to be placed today.
class _ForceCheck {
  _ForceCheck(this.mask, this.minWeight);

  final int mask;
  final int minWeight;
  int left = 0;

  bool has(_Candidate candidate) =>
      candidate.weight >= minWeight &&
      (mask == _anyDay ||
          (candidate.dayMask != _anyDay && candidate.dayMask & ~mask == 0));
}

/// Running totals of the free base room (no overflow) of the days from
/// today on, in half-slots (D21), extended on demand. A day's free room is
/// `2 × capacity` minus the weight pinned on it, never below 0.
class _FutureCapacity {
  _FutureCapacity(this._resolver, this._today, this._pinnedOn)
    : _todayWeekday = _today.weekday;

  final CapacityResolver _resolver;
  final LocalDate _today;
  final int _todayWeekday;

  /// Pinned weight per day offset; those half-slots are already taken.
  final Map<int, int> _pinnedOn;

  /// Per set of weekdays, when none of them has capacity in the week: the
  /// first offset after the last override that grants some on such a day.
  /// From there on nothing is ever added. -1 when the set has capacity.
  final Map<int, int> _zeroFrom = {};

  /// Free room of the offsets `0, 1, ...` computed so far.
  final List<int> _free = [];

  /// `_sumsAll[k]` = the free room of the offsets `0 .. k - 1`.
  final List<int> _sumsAll = [0];

  /// The same per minimum free room and set of weekdays, counting only the
  /// days that have at least that much and are in the set (rare: heavy due
  /// tasks, due tasks limited to some weekdays).
  final Map<int, List<int>> _sums = {};

  /// Free room of the days after offset [after] up to and including
  /// [until], counting only the days with at least [minFree] (D21: a heavy
  /// task does not count on a day too small for it) and on a weekday of
  /// [mask] (D23: a task does not count on a day it may not take).
  ///
  /// Counting stops as soon as the result reaches [enough]: the caller only
  /// needs to know that there is at least that much, and a due date decades
  /// away must not make the planner walk there day by day.
  int between(
    int after,
    int until, {
    required int enough,
    int minFree = 0,
    int mask = _anyDay,
  }) {
    if (until <= after) return 0;
    final sums = minFree == 0 && mask == _anyDay
        ? _sumsAll
        : (_sums[minFree * (_anyDay + 1) + mask] ??= [0]);
    final from = after + 1;
    while (sums.length <= from) {
      _append(sums, minFree, mask);
    }
    final allZeroFrom = _allZeroFrom(mask);
    while (sums.length <= until + 1) {
      if (sums.last - sums[from] >= enough) break;
      if (allZeroFrom >= 0 && sums.length - 1 >= allZeroFrom) break;
      _append(sums, minFree, mask);
    }
    final to = until + 1 < sums.length ? until + 1 : sums.length - 1;
    return sums[to] - sums[from];
  }

  /// Adds the next day to [sums], the running totals for [minFree] and
  /// [mask].
  void _append(List<int> sums, int minFree, int mask) {
    final offset = sums.length - 1;
    while (_free.length <= offset) {
      final room =
          2 * _resolver.capacityFor(_today.addDays(_free.length)) -
          (_pinnedOn[_free.length] ?? 0);
      _free.add(room > 0 ? room : 0);
    }
    final free = _free[offset];
    final counts =
        free >= minFree && (mask >> ((_todayWeekday + offset) % 7)) & 1 == 1;
    sums.add(sums.last + (counts ? free : 0));
  }

  /// See [_zeroFrom].
  int _allZeroFrom(int mask) => _zeroFrom[mask] ??= _findAllZeroFrom(mask);

  int _findAllZeroFrom(int mask) {
    final weekly = _resolver.settings.weeklyCapacity;
    for (var day = 0; day < 7; day++) {
      if ((mask >> day) & 1 == 1 && weekly[day] > 0) return -1;
    }
    var from = 0;
    for (final MapEntry(key: date, value: override)
        in _resolver.overrides.entries) {
      if (override.capacity == 0) continue;
      if ((mask >> date.weekday) & 1 == 0) continue;
      final next = _today.daysUntil(date) + 1;
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
