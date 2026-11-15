import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';

/// T-704: the repeats of recurring tasks as ghosts in the plan. Scenario
/// numbers refer to "Test scenarios" in docs/04 Planner Algorithm.md.
void main() {
  // Monday.
  final today = LocalDate(2026, 11, 16);
  final epoch = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 16, 9);
  LocalDate day(int offset) => today.addDays(offset);

  const everyDayOne = [1, 1, 1, 1, 1, 1, 1];
  final noBoost = Settings(urgencySoonDays: 0, urgencyNearDays: 0);

  Task task(
    String id, {
    int level = PriorityLabels.normal,
    int age = 0,
    LocalDate? due,
    LocalDate? pin,
  }) => Task.create(
    id: id,
    title: id,
    priority: level,
    dueDate: due,
    now: epoch.add(Duration(minutes: age)),
  ).copyWith(pinnedDate: pin);

  Task repeating(Task t, Recurrence rule, {LocalDate? startedOn}) =>
      t.setRecurrence(rule, today: startedOn ?? today, now: now);

  Recurrence weekly() =>
      Recurrence.interval(every: 1, unit: RecurrenceUnit.week, anchor: today);

  Plan plan(List<Task> tasks, {Settings? settings, LocalDate? on}) =>
      const Planner().plan(
        activeTasks: tasks,
        settings: settings ?? Settings(),
        overrides: const {},
        today: on ?? today,
      );

  /// Every entry of [id]: (day, occurrence date of a ghost or null).
  List<(LocalDate, LocalDate?)> placements(Plan plan, String id) => [
    for (final d in plan.days)
      for (final e in d.entries)
        if (e.taskId == id) (d.date, e.occurrenceDate),
  ];

  List<PlanEntry> ghosts(Plan plan) => [
    for (final d in plan.days)
      for (final e in d.entries)
        if (e.isGhost) e,
  ];

  test('26. weekly without dates: the instance and a ghost a week', () {
    final w = repeating(task('W'), weekly());
    final result = plan([w], settings: Settings(planningHorizonDays: 30));

    expect(placements(result, 'W'), [
      (day(0), null),
      (day(7), day(7)),
      (day(14), day(14)),
      (day(21), day(21)),
      (day(28), day(28)),
    ]);
    expect(result.laterTaskIds, isEmpty);
    expect(result.focus, isEmpty);
    expect(
      ghosts(result).every((e) => e.reason == PlanReason.priority),
      isTrue,
    );
  });

  test('26. a ghost waits for its release day or the next free one', () {
    // Capacity 1; the Monday a week on is taken by a pinned task, so the
    // ghost released that day goes to Tuesday.
    final w = repeating(task('W'), weekly());
    final blocker = task('B', level: 2, pin: day(7));
    final result = plan(
      [w, blocker],
      settings: noBoost.copyWith(
        weeklyCapacity: everyDayOne,
        planningHorizonDays: 10,
      ),
    );

    expect(placements(result, 'W'), [(day(0), null), (day(8), day(7))]);
  });

  test('27. monthly by schedule from Jan 31: month ends', () {
    final jan31 = LocalDate(2027, 1, 31);
    final rule = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.month,
      anchor: jan31,
    );
    final m = task('M').setRecurrence(rule, today: jan31, now: now);
    final result = plan(
      [m],
      on: jan31,
      settings: Settings(weeklyCapacity: everyDayOne, planningHorizonDays: 90),
    );

    expect(
      [for (final e in ghosts(result)) e.occurrenceDate],
      [LocalDate(2027, 2, 28), LocalDate(2027, 3, 31), LocalDate(2027, 4, 30)],
    );
  });

  test('28. pinned weekdays: ghosts pinned, on a rest day too, and they '
      'take the room of deadlines', () {
    // Mon, Wed, Fri, Sun; pinned on today (Mon).
    final rule = Recurrence.weekdays(const {0, 2, 4, 6});
    final p = repeating(task('P', pin: today), rule);
    final dues = [
      for (var i = 1; i <= 3; i++) task('D$i', age: i, due: day(4)),
    ];
    final result = plan(
      [p, ...dues],
      settings: noBoost.copyWith(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 0],
        planningHorizonDays: 7,
      ),
    );

    expect(placements(result, 'P'), [
      (day(0), null),
      (day(2), day(2)),
      (day(4), day(4)),
      (day(6), day(6)),
    ]);
    expect(ghosts(result).every((e) => e.reason == PlanReason.pinned), isTrue);
    // Three tasks due Fri; Wed and Fri are taken by the ghosts, so Tue and
    // Thu are free: one of the three has to be done on Monday.
    final monday = result.days.first.entries.map((e) => e.taskId).toList();
    expect(monday, ['P', 'D1']);
  });

  test('29. due-only weekly: each ghost inside its own week', () {
    final rule = weekly();
    final w = repeating(task('W', level: 1, due: today), rule);
    final result = plan(
      [w],
      settings: Settings(
        weeklyCapacity: const [3, 3, 3, 3, 3, 3, 3],
        planningHorizonDays: 22,
      ),
    );

    // Released the day after the previous repeat, so never two in one week.
    expect(placements(result, 'W'), [
      (day(0), null),
      (day(1), day(7)),
      (day(8), day(14)),
      (day(15), day(21)),
    ]);
  });

  test('30. a missed instance is one overdue task; ghosts start after '
      'today', () {
    // Mon, Wed, Fri; the instance of Fri Nov 13 was not done.
    final rule = Recurrence.weekdays(const {0, 2, 4});
    final fri = day(-3);
    final m = task('M', due: fri).setRecurrence(rule, today: fri, now: now);
    final result = plan([m], settings: Settings(planningHorizonDays: 7));

    expect(result.focus.single.taskId, 'M');
    expect(result.focus.single.overdueDays, 3);
    final occurrences = [for (final e in ghosts(result)) e.occurrenceDate];
    expect(occurrences.first, day(2));
    expect(occurrences, isNot(contains(today)));
  });

  test('31. from completion: no ghosts, only the instance; its successor '
      'from the day it is done (T-712)', () {
    final rule = Recurrence.interval(
      every: 10,
      unit: RecurrenceUnit.day,
      afterDone: true,
    );
    final a = repeating(task('A'), rule);
    final settings = Settings(
      weeklyCapacity: everyDayOne,
      planningHorizonDays: 30,
    );

    final before = plan([a], settings: settings);
    expect(placements(before, 'A'), [(day(0), null)]);
    expect(ghosts(before), isEmpty);
    // The free places are not taken by guesses.
    expect(before.days[10].entries, isEmpty);

    final next = a.successor(now: now, today: today);
    final after = plan([next], settings: settings);
    expect(placements(after, next.id), [(day(10), null)]);
    expect(ghosts(after), isEmpty);
  });

  test('31b. a pinned rule from completion has no ghosts either; a rule by '
      'the calendar beside it keeps its own', () {
    final fromDone = repeating(
      task('A', pin: day(2)),
      Recurrence.interval(every: 3, unit: RecurrenceUnit.day, afterDone: true),
    );
    final w = repeating(task('W'), weekly());
    final result = plan([
      fromDone,
      w,
    ], settings: Settings(planningHorizonDays: 15));

    expect(placements(result, 'A'), [(day(2), null)]);
    expect([for (final e in ghosts(result)) e.taskId], ['W', 'W']);
  });

  test('32. a ghost that misses its date is at risk on its entry only', () {
    // Due-only weekly: the ghost due Mon day(7) is released Tue day(1).
    // Every day of its week is taken by a pin, capacity 1, no overflow.
    final w = repeating(task('W', due: today), weekly());
    final pins = [
      for (var i = 1; i <= 7; i++) task('P$i', age: i, pin: day(i)),
    ];
    final settings = noBoost.copyWith(
      weeklyCapacity: everyDayOne,
      maxOverflowPerDay: 0,
      planningHorizonDays: 10,
    );
    final result = plan([w, ...pins], settings: settings);

    final ghost = ghosts(result).first;
    expect(ghost.occurrenceDate, day(7));
    expect(ghost.atRisk, isTrue);
    expect(result.atRiskTaskIds, isNot(contains('W')));

    // The same with a horizon that ends on its due date: no day for it,
    // dropped, not in later.
    final short = plan([
      w,
      ...pins,
    ], settings: settings.copyWith(planningHorizonDays: 8));
    expect(ghosts(short), isEmpty);
    expect(short.laterTaskIds, isNot(contains('W')));
  });

  test('a ghost is never placed today and never in Focus', () {
    final daily = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.day,
      anchor: today,
    );
    final f = repeating(task('F'), daily).setFocus(true, now);
    final result = plan(
      [f],
      settings: Settings(
        weeklyCapacity: const [5, 5, 5, 5, 5, 5, 5],
        planningHorizonDays: 5,
      ),
    );

    expect(result.days.first.entries.where((e) => e.isGhost), isEmpty);
    expect(result.focus.map((e) => e.taskId), ['F']);
    expect(ghosts(result), hasLength(4));
  });

  group('33b. repeats of a series do not pile up (found on the emulator)', () {
    // Mon, Tue, Thu, Sat without dates, made today (Mon); four older tasks
    // fill Mon..Thu, capacity 1 on working days and 3 on Saturday.
    final rule = Recurrence.weekdays(const {0, 1, 3, 5});
    List<Task> tasks() => [
      for (var i = 1; i <= 4; i++) task('F$i', age: i),
      repeating(task('R', age: 10), rule),
    ];
    final settings = Settings(planningHorizonDays: 14);

    test('never two of a series on one day', () {
      final result = plan(tasks(), settings: settings);

      for (final d in result.days) {
        expect(
          d.entries.where((e) => e.taskId == 'R'),
          hasLength(lessThanOrEqualTo(1)),
          reason: '${d.date}',
        );
      }
    });

    test('a repeat never comes before the task itself', () {
      final result = plan(tasks(), settings: settings);
      final r = placements(result, 'R');

      expect(r.first, (day(4), null));
      expect(r.skip(1).every((p) => p.$1 > day(4)), isTrue);
    });

    test('a repeat without dates that misses its turn is dropped', () {
      final result = plan(tasks(), settings: settings);

      // Tue 17 and Thu 19 found no day before the next date of the rule;
      // Sat 21 is the first repeat after the task (Fri 20).
      expect(placements(result, 'R').take(3), [
        (day(4), null),
        (day(5), day(5)),
        (day(7), day(7)),
      ]);
    });

    test('a due-only repeat waits for the one before it', () {
      // Daily due-only series, capacity 1, one older task due today: the
      // instance goes to Tuesday, its first repeat cannot sit before it.
      final daily = Recurrence.interval(
        every: 1,
        unit: RecurrenceUnit.day,
        anchor: today,
      );
      final result = plan(
        [
          task('X', level: 1, due: today),
          repeating(task('D', age: 5, due: today), daily),
        ],
        settings: noBoost.copyWith(
          weeklyCapacity: everyDayOne,
          maxOverflowPerDay: 0,
          planningHorizonDays: 5,
        ),
      );

      final days = [for (final p in placements(result, 'D')) p.$1];
      for (var i = 1; i < days.length; i++) {
        expect(days[i] > days[i - 1], isTrue, reason: '$days');
      }
    });
  });

  group('33. determinism and performance with ghosts', () {
    final daily = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.day,
      anchor: today,
    );
    List<Task> manyTasks() => [
      for (var i = 0; i < 500; i++)
        () {
          final t = task(
            't$i',
            level: 1 + i % 10,
            age: i,
            due: i % 3 == 0 ? day(i % 120 - 5) : null,
          );
          return i % 25 == 0 ? repeating(t, daily) : t;
        }(),
    ];

    test('the same plan twice', () {
      final tasks = manyTasks();

      expect(plan(tasks), plan(tasks));
      expect(plan(tasks.reversed.toList()), plan(tasks));
    });

    test('500 tasks with 20 daily series over 90 days in under 50 ms', () {
      final tasks = manyTasks();
      plan(tasks);
      var best = const Duration(days: 1);
      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        plan(tasks);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }

      expect(best, lessThan(const Duration(milliseconds: 50)));
    });
  });
}
