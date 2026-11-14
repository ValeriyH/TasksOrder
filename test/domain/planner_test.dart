import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';

/// Scenario numbers refer to "Test scenarios" in docs/04 Planner Algorithm.md.
void main() {
  // Monday.
  final today = LocalDate(2026, 11, 16);
  final epoch = DateTime.utc(2026, 11, 1);

  const everyDayOne = [1, 1, 1, 1, 1, 1, 1];

  /// Thresholds 0 / 0 leave only deadline forcing.
  final noBoost = Settings(urgencySoonDays: 0, urgencyNearDays: 0);

  /// A task whose id doubles as its title. [priority] is the position on the
  /// default scale 5, as in the examples of docs/04: 1 Critical, 2 High,
  /// 3 Normal, 4 Low, 5 Someday ([level] sets a level of the table instead).
  /// [age] orders `createdAt`: a lower value is an older task. [focused] is
  /// the minute the Focus mark was set.
  Task task(
    String id,
    int priority, {
    required int age,
    LocalDate? due,
    int? focused,
    int? level,
  }) {
    final t = Task.create(
      id: id,
      title: id,
      priority: level ?? PriorityLabels.fromPosition(priority, 5),
      dueDate: due,
      now: epoch.add(Duration(minutes: age)),
    );
    return focused == null
        ? t
        : t.setFocus(true, epoch.add(Duration(days: 1, minutes: focused)));
  }

  Plan plan(
    List<Task> tasks, {
    Settings? settings,
    List<DayOverride> overrides = const [],
    int completedTodayCount = 0,
  }) => const Planner().plan(
    activeTasks: tasks,
    settings: settings ?? Settings(),
    overrides: {for (final o in overrides) o.date: o},
    today: today,
    completedTodayCount: completedTodayCount,
  );

  /// Non-empty days as `{'2026-11-16': ['a', 'b']}`.
  Map<String, List<String>> schedule(Plan plan) => {
    for (final day in plan.days)
      if (day.entries.isNotEmpty)
        day.date.toIso(): [for (final e in day.entries) e.taskId],
  };

  /// The whole Focus view, in its order.
  List<String> focusIds(Plan plan) => [for (final e in plan.focus) e.taskId];

  /// The Focus strip: what is not on today's list, up to the visible limit.
  List<String> stripIds(Plan plan) => [
    for (final e in plan.visibleFocus) e.taskId,
  ];

  PlanEntry entryOf(Plan plan, String id) =>
      [for (final day in plan.days) ...day.entries]
          .singleWhere((e) => e.taskId == id);

  List<String> plannedIds(Plan plan) => [
    for (final day in plan.days)
      for (final e in day.entries) e.taskId,
  ];

  group('shape of the plan', () {
    test('1. empty pool: every day empty, no later, no focus', () {
      final p = plan([]);

      expect(p.today, today);
      expect(p.days, hasLength(90));
      expect(p.days.first.date, today);
      expect(p.days.last.date, today.addDays(89));
      expect(p.days.every((d) => d.entries.isEmpty), isTrue);
      expect(p.laterTaskIds, isEmpty);
      expect(p.atRiskTaskIds, isEmpty);
      expect(p.focus, isEmpty);
    });

    test('days are consecutive and carry their capacity', () {
      final p = plan([], settings: Settings(planningHorizonDays: 8));

      expect(
        [for (final d in p.days) d.date],
        [for (var i = 0; i < 8; i++) today.addDays(i)],
      );
      expect([for (final d in p.days) d.capacity], [1, 1, 1, 1, 1, 3, 0, 1]);
    });

    test('focusVisibleLimit comes from the settings', () {
      expect(plan([]).focusVisibleLimit, 3);
      expect(
        plan([], settings: Settings(focusVisibleLimit: 5)).focusVisibleLimit,
        5,
      );
    });
  });

  group('priority fill', () {
    test('2. no due dates, capacity 1: priority order, ties by age', () {
      final p = plan([
        task('normal-old', 3, age: 1),
        task('high-new', 2, age: 5),
        task('critical', 1, age: 9),
        task('high-old', 2, age: 2),
        task('normal-new', 3, age: 7),
      ], settings: Settings(weeklyCapacity: everyDayOne));

      expect(schedule(p), {
        '2026-11-16': ['critical'],
        '2026-11-17': ['high-old'],
        '2026-11-18': ['high-new'],
        '2026-11-19': ['normal-old'],
        '2026-11-20': ['normal-new'],
      });
      expect(p.laterTaskIds, isEmpty);
    });

    test('every entry is a plain priority pick', () {
      final p = plan([task('a', 1, age: 1), task('b', 2, age: 2)]);
      for (final day in p.days) {
        for (final e in day.entries) {
          expect(e.reason, PlanReason.priority);
          expect(e.overflow, isFalse);
          expect(e.atRisk, isFalse);
        }
        expect(day.isOverloaded, isFalse);
      }
    });

    test('within a priority an earlier due date goes first', () {
      final p = plan([
        task('no-due', 2, age: 1),
        task('due-later', 2, age: 2, due: today.addDays(40)),
        task('due-sooner', 2, age: 3, due: today.addDays(30)),
      ], settings: Settings(weeklyCapacity: everyDayOne));

      expect(plannedIds(p), ['due-sooner', 'due-later', 'no-due']);
    });

    test('3. weekday capacity is respected, Sunday 0 is skipped', () {
      final p = plan([for (var i = 1; i <= 10; i++) task('t$i', 3, age: i)]);

      expect(schedule(p), {
        '2026-11-16': ['t1'], // Mon
        '2026-11-17': ['t2'],
        '2026-11-18': ['t3'],
        '2026-11-19': ['t4'],
        '2026-11-20': ['t5'], // Fri
        '2026-11-21': ['t6', 't7', 't8'], // Sat
        // Sun 22: rest day
        '2026-11-23': ['t9'], // Mon
        '2026-11-24': ['t10'],
      });
      final sunday = p.days[6];
      expect(sunday.date, LocalDate(2026, 11, 22));
      expect(sunday.capacity, 0);
      expect(sunday.entries, isEmpty);
    });

    test('4. a day override replaces the capacity of its date only', () {
      final tuesday = today.addDays(1);
      final p = plan(
        [for (var i = 1; i <= 12; i++) task('t$i', 3, age: i)],
        overrides: [DayOverride(date: tuesday, capacity: 3)],
      );

      expect(schedule(p), {
        '2026-11-16': ['t1'],
        '2026-11-17': ['t2', 't3', 't4'], // overridden Tuesday
        '2026-11-18': ['t5'],
        '2026-11-19': ['t6'],
        '2026-11-20': ['t7'],
        '2026-11-21': ['t8', 't9', 't10'],
        '2026-11-23': ['t11'],
        '2026-11-24': ['t12'], // next Tuesday is back to 1
      });
      expect(p.days[1].capacity, 3);
      expect(p.days[8].capacity, 1);
    });

    test('an override of 0 makes a working day a rest day', () {
      final p = plan(
        [task('a', 1, age: 1), task('b', 1, age: 2)],
        overrides: [DayOverride(date: today, capacity: 0)],
      );

      expect(schedule(p), {
        '2026-11-17': ['a'],
        '2026-11-18': ['b'],
      });
    });

    test('with no capacity at all every task is later', () {
      final p = plan([
        task('b', 2, age: 1),
        task('a', 1, age: 2),
      ], settings: Settings(weeklyCapacity: [0, 0, 0, 0, 0, 0, 0]));

      expect(plannedIds(p), isEmpty);
      expect(p.laterTaskIds, ['a', 'b']);
    });

    test('a task due today is not overdue', () {
      final p = plan([task('a', 3, age: 1, due: today)]);

      expect(p.focus, isEmpty);
      expect(schedule(p), {
        '2026-11-16': ['a'],
      });
    });

    test('done and deleted tasks are ignored', () {
      final now = epoch.add(const Duration(days: 2));
      final p = plan([
        task('done', 1, age: 1).complete(now, onPlan: true),
        task('deleted', 1, age: 2).trash(now),
        task(
          'focused-done',
          1,
          age: 3,
          focused: 1,
        ).complete(now, onPlan: false),
        task('overdue-deleted', 1, age: 4, due: today.addDays(-2)).trash(now),
        task('active', 3, age: 5),
      ]);

      expect(plannedIds(p), ['active']);
      expect(p.focus, isEmpty);
      expect(p.laterTaskIds, isEmpty);
    });
  });

  group('completed today', () {
    final tasks = [for (var i = 1; i <= 4; i++) task('t$i', 3, age: i)];

    test('lowers today\'s capacity so the slot is not refilled', () {
      final p = plan(
        tasks,
        settings: Settings(weeklyCapacity: [2, 1, 1, 1, 1, 1, 1]),
        completedTodayCount: 1,
      );

      expect(p.days.first.capacity, 1);
      expect(schedule(p)['2026-11-16'], ['t1']);
      expect(schedule(p)['2026-11-17'], ['t2']);
    });

    test('with the whole capacity done nothing new is picked today', () {
      final p = plan(tasks, completedTodayCount: 1);

      expect(p.days.first.capacity, 0);
      expect(p.days.first.entries, isEmpty);
      expect(schedule(p)['2026-11-17'], ['t1']);
    });

    test('capacity never drops below 0', () {
      final p = plan(tasks, completedTodayCount: 5);

      expect(p.days.first.capacity, 0);
      expect(p.days[1].capacity, 1);
    });

    test('only today is affected', () {
      final p = plan(
        tasks,
        settings: Settings(weeklyCapacity: everyDayOne),
        completedTodayCount: 1,
      );

      expect([for (final d in p.days.take(3)) d.capacity], [0, 1, 1]);
    });
  });

  group('overdue tasks (D18)', () {
    test('10. an overdue task is planned by priority only and is in Focus', () {
      final p = plan([
        task('overdue', 4, age: 1, due: today.addDays(-1)),
        task('plain', 3, age: 2),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['plain'],
        '2026-11-17': ['overdue'],
      });
      expect(p.focus, [
        FocusEntry(
          taskId: 'overdue',
          focused: false,
          overdueDays: 1,
          plannedDate: today.addDays(1),
        ),
      ]);
      expect(p.days.first.capacity, 1);
    });

    test('10. it is not forced, not boosted and never at risk', () {
      final p = plan([
        task('high-1', 1, age: 1),
        task('high-2', 1, age: 2),
        task('normal', 3, age: 3),
        task('overdue-low', 4, age: 4, due: today.addDays(-3)),
      ], settings: Settings(weeklyCapacity: everyDayOne));

      expect(plannedIds(p), ['high-1', 'high-2', 'normal', 'overdue-low']);
      final entry = entryOf(p, 'overdue-low');
      expect(entry.reason, PlanReason.priority);
      expect(entry.atRisk, isFalse);
      expect(entry.overflow, isFalse);
      expect(p.atRiskTaskIds, isEmpty);
      expect(p.days.any((d) => d.isOverloaded), isFalse);
    });

    test('within a priority it is ordered like a task without a due date', () {
      final p = plan([
        task('plain-old', 3, age: 1),
        task('overdue', 3, age: 2, due: today.addDays(-4)),
        task('plain-new', 3, age: 3),
        task('due-far', 3, age: 4, due: today.addDays(40)),
      ], settings: Settings(weeklyCapacity: everyDayOne));

      expect(plannedIds(p), ['due-far', 'plain-old', 'overdue', 'plain-new']);
    });

    test('10. overdueDays counts the days since the due date', () {
      final p = plan([task('old', 3, age: 1, due: today.addDays(-12))]);

      expect(p.focus.single.overdueDays, 12);
      expect(p.focus.single.isOverdue, isTrue);
    });

    test('10. moving the due date forward takes the task out of Focus', () {
      final p = plan([task('moved', 4, age: 1, due: today.addDays(1))]);

      expect(p.focus, isEmpty);
      expect(plannedIds(p), ['moved']);
    });

    test('an overdue task that does not fit the horizon is later and has no '
        'planned date', () {
      final p = plan([
        task('high', 1, age: 1),
        task('overdue', 4, age: 2, due: today.addDays(-1)),
      ], settings: Settings(planningHorizonDays: 1));

      expect(plannedIds(p), ['high']);
      expect(p.laterTaskIds, ['overdue']);
      expect(p.focus.single.plannedDate, isNull);
      expect(stripIds(p), ['overdue']);
    });

    test('a pinned overdue task keeps its pin and is not at risk', () {
      final wednesday = today.addDays(2);
      final p = plan([
        task(
          'pinned',
          3,
          age: 1,
          due: today.addDays(-1),
        ).copyWith(pinnedDate: wednesday),
      ]);

      expect(schedule(p), {
        '2026-11-18': ['pinned'],
      });
      expect(entryOf(p, 'pinned').reason, PlanReason.pinned);
      expect(p.atRiskTaskIds, isEmpty);
      expect(p.focus.single.plannedDate, wednesday);
    });
  });

  group('Focus (D17)', () {
    test('a focused task keeps its place in the plan', () {
      List<Task> tasks({required bool focused}) => [
        task('high', 2, age: 1),
        task('normal', 3, age: 2, focused: focused ? 1 : null),
        task('low', 4, age: 3),
      ];

      final marked = plan(tasks(focused: true));
      expect(schedule(marked), schedule(plan(tasks(focused: false))));
      expect(marked.focus, [
        FocusEntry(
          taskId: 'normal',
          focused: true,
          plannedDate: today.addDays(1),
        ),
      ]);
    });

    test('a focused task on today\'s list is not in the strip', () {
      final p = plan([
        task('no-due', 3, age: 1, focused: 1),
        task('due-today', 3, age: 2, focused: 2, due: today),
        task('due-later', 3, age: 3, focused: 3, due: today.addDays(5)),
      ]);

      expect(schedule(p)['2026-11-16'], ['due-today']);
      expect(focusIds(p), ['due-today', 'due-later', 'no-due']);
      expect(stripIds(p), ['due-later', 'no-due']);
      for (final e in p.focus) {
        expect(e.focused, isTrue);
        expect(e.overdueDays, 0);
        expect(e.plannedDate, isNotNull);
      }
    });

    test('a focused overdue task is both focused and overdue', () {
      final p = plan([
        task('a', 3, age: 1, focused: 1, due: today.addDays(-3)),
      ]);

      expect(p.focus, [
        FocusEntry(
          taskId: 'a',
          focused: true,
          overdueDays: 3,
          plannedDate: today,
        ),
      ]);
      expect(stripIds(p), isEmpty);
    });

    test('15. five focused tasks: Focus order is (priority, due, focusedAt), '
        'all stay planned, the strip shows three that are not on today', () {
      final tasks = [
        task('normal-focused-late', 3, age: 1, focused: 9),
        task('high-no-due', 2, age: 2, focused: 5),
        task('normal-focused-early', 3, age: 3, focused: 2),
        task('high-due', 2, age: 4, focused: 7, due: today.addDays(3)),
        task('critical', 1, age: 5, focused: 8),
        task('plain-1', 2, age: 6),
        task('plain-2', 2, age: 7),
      ];
      final p = plan(tasks);

      expect(focusIds(p), [
        'critical',
        'high-due',
        'high-no-due',
        'normal-focused-early',
        'normal-focused-late',
      ]);
      // Pool order: the Focus mark does not count, age does.
      expect(plannedIds(p), [
        'critical',
        'high-due',
        'high-no-due',
        'plain-1',
        'plain-2',
        'normal-focused-late',
        'normal-focused-early',
      ]);
      expect(p.days.first.capacity, 1);
      expect(stripIds(p), ['high-due', 'high-no-due', 'normal-focused-early']);
      expect(p.hiddenFocusCount, 1);
    });

    test('15. completing one keeps the order of the rest', () {
      final tasks = [
        task('normal-late', 3, age: 1, focused: 9),
        task('high', 2, age: 2, focused: 5),
        task('normal-early', 3, age: 3, focused: 2),
        task('low', 4, age: 4, focused: 1),
        task('critical', 1, age: 5, focused: 8),
      ];
      final remaining = tasks.where((t) => t.id != 'high').toList();
      final p = plan(remaining);

      expect(focusIds(p), ['critical', 'normal-early', 'normal-late', 'low']);
      expect(stripIds(p), ['normal-early', 'normal-late', 'low']);
      expect(p.hiddenFocusCount, 0);
    });

    test('15b. focused and overdue together: priority wins, overdue leads '
        'only within a priority', () {
      final p = plan([
        task('normal-focused', 3, age: 1, focused: 1),
        task('low-overdue', 4, age: 2, due: today.addDays(-5)),
        task('high-overdue', 2, age: 3, due: today.addDays(-1)),
        task('normal-overdue', 3, age: 4, due: today.addDays(-2)),
      ]);

      expect(focusIds(p), [
        'high-overdue',
        'normal-overdue',
        'normal-focused',
        'low-overdue',
      ]);
      // In the plan the overdue date is ignored: priority, then age.
      expect(plannedIds(p), [
        'high-overdue',
        'normal-focused',
        'normal-overdue',
        'low-overdue',
      ]);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('equal overdue tasks keep their age order', () {
      final p = plan([
        task('newer', 3, age: 5, due: today.addDays(-2)),
        task('older', 3, age: 1, due: today.addDays(-2)),
      ]);

      expect(focusIds(p), ['older', 'newer']);
    });

    test('a focused task keeps its deadline forcing', () {
      final p = plan([
        task('focused-due-today', 5, age: 1, focused: 1, due: today),
        task('plain', 3, age: 2),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['focused-due-today'],
        '2026-11-17': ['plain'],
      });
      expect(entryOf(p, 'focused-due-today').reason, PlanReason.deadline);
      expect(focusIds(p), ['focused-due-today']);
      expect(stripIds(p), isEmpty);
    });

    test('a focused pinned task keeps its pin', () {
      final wednesday = today.addDays(2);
      final p = plan([
        task('focused', 3, age: 1, focused: 1).copyWith(pinnedDate: wednesday),
      ]);

      expect(schedule(p), {
        '2026-11-18': ['focused'],
      });
      expect(entryOf(p, 'focused').reason, PlanReason.pinned);
      expect(p.focus.single.plannedDate, wednesday);
      expect(stripIds(p), ['focused']);
    });
  });

  /// Worked example 1 in docs/04 Planner Algorithm.md.
  List<Task> example1() => [
    task('K', 3, age: 1, focused: 1),
    task('A', 2, age: 2),
    task('F', 2, age: 3),
    task('B', 3, age: 4),
    task('E', 3, age: 5, due: LocalDate(2026, 11, 21)),
    task('C', 4, age: 6, due: LocalDate(2026, 11, 17)),
    task('D', 5, age: 7, due: LocalDate(2026, 11, 18)),
  ];

  group('deadline forcing', () {
    test('6. worked example 1 without boost: a Low task with a deadline '
        'pushes a High one', () {
      final p = plan(example1(), settings: noBoost);

      expect(schedule(p), {
        '2026-11-16': ['A'], // Mon
        '2026-11-17': ['C'], // Tue, forced
        '2026-11-18': ['D'], // Wed, forced
        '2026-11-19': ['F'], // Thu
        '2026-11-20': ['E'], // Fri
        '2026-11-21': ['K', 'B'], // Sat, one slot stays empty
      });
      // K is focused: planned on Saturday like any Normal task, and in the
      // strip until then.
      expect(stripIds(p), ['K']);
      expect(p.focus.single.plannedDate, LocalDate(2026, 11, 21));
      expect(entryOf(p, 'K').reason, PlanReason.priority);
      expect(entryOf(p, 'A').reason, PlanReason.priority);
      expect(entryOf(p, 'C').reason, PlanReason.deadline);
      expect(entryOf(p, 'D').reason, PlanReason.deadline);
      expect(entryOf(p, 'F').reason, PlanReason.priority);
      expect(entryOf(p, 'E').reason, PlanReason.priority);
      expect(entryOf(p, 'B').reason, PlanReason.priority);
      expect(p.atRiskTaskIds, isEmpty);
      expect(p.days.any((d) => d.isOverloaded), isFalse);
    });

    test('a task due today is forced today over a higher priority', () {
      final p = plan([
        task('high', 1, age: 1),
        task('due-today', 5, age: 2, due: today),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['due-today'],
        '2026-11-17': ['high'],
      });
      expect(entryOf(p, 'due-today').reason, PlanReason.deadline);
      expect(entryOf(p, 'due-today').overflow, isFalse);
    });

    test('a deadline with enough room before it forces nothing', () {
      final p = plan([
        task('high', 1, age: 1),
        task('due-friday', 5, age: 2, due: today.addDays(4)),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['high'],
        '2026-11-17': ['due-friday'],
      });
      expect(entryOf(p, 'due-friday').reason, PlanReason.priority);
    });

    test('10. an overdue task moved to tomorrow is forced tomorrow', () {
      final p = plan([
        task('high-1', 1, age: 1),
        task('high-2', 1, age: 2),
        task('moved', 4, age: 3, due: today.addDays(1)),
      ]);

      expect(p.focus, isEmpty);
      expect(schedule(p), {
        '2026-11-16': ['high-1'],
        '2026-11-17': ['moved'],
        '2026-11-18': ['high-2'],
      });
      expect(entryOf(p, 'moved').reason, PlanReason.deadline);
    });

    test('among forced tasks the earliest deadline goes first', () {
      final p = plan([
        task('due-wed-high', 1, age: 1, due: today.addDays(2)),
        task('due-tue-low', 5, age: 2, due: today.addDays(1)),
        task('due-mon-low', 5, age: 3, due: today),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['due-mon-low'],
        '2026-11-17': ['due-tue-low'],
        '2026-11-18': ['due-wed-high'],
      });
    });

    test('11. a task due on a rest day is forced on the previous working '
        'day', () {
      final sunday = LocalDate(2026, 11, 22);
      final p = plan([
        for (var i = 1; i <= 10; i++) task('h$i', 2, age: i),
        task('due-sunday', 5, age: 20, due: sunday),
      ]);

      expect(schedule(p)['2026-11-21'], ['due-sunday', 'h6', 'h7']);
      expect(entryOf(p, 'due-sunday').reason, PlanReason.deadline);
      expect(p.days[6].entries, isEmpty); // Sunday
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('11. more rest-day deadlines than Saturday holds start earlier', () {
      final sunday = LocalDate(2026, 11, 22);
      final p = plan([
        for (var i = 1; i <= 6; i++) task('h$i', 2, age: i),
        for (var i = 1; i <= 4; i++) task('d$i', 5, age: 10 + i, due: sunday),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['h1'],
        '2026-11-17': ['h2'],
        '2026-11-18': ['h3'],
        '2026-11-19': ['h4'],
        '2026-11-20': ['d1'], // Fri: Saturday holds only three
        '2026-11-21': ['d2', 'd3', 'd4'],
        '2026-11-23': ['h5'],
        '2026-11-24': ['h6'],
      });
      expect(p.days.any((d) => d.isOverloaded), isFalse);
    });

    test('an override of 0 before a deadline pulls the task earlier', () {
      final p = plan(
        [
          task('high-1', 1, age: 1),
          task('high-2', 1, age: 2),
          task('due-wed', 5, age: 3, due: today.addDays(2)),
        ],
        overrides: [
          DayOverride(date: today.addDays(1), capacity: 0),
          DayOverride(date: today.addDays(2), capacity: 0),
        ],
      );

      expect(schedule(p), {
        '2026-11-16': ['due-wed'],
        '2026-11-19': ['high-1'],
        '2026-11-20': ['high-2'],
      });
    });

    test('a due date decades away does not slow the plan down', () {
      final watch = Stopwatch()..start();
      final p = plan([
        task('far', 3, age: 1, due: LocalDate(9999, 12, 31)),
        task('plain', 1, age: 2),
      ]);
      watch.stop();

      expect(plannedIds(p), ['plain', 'far']);
      expect(entryOf(p, 'far').reason, PlanReason.priority);
      expect(watch.elapsedMilliseconds, lessThan(200));
    });

    test('with no capacity anywhere a far due date still terminates', () {
      final p = plan([
        task('far', 3, age: 1, due: LocalDate(9999, 12, 31)),
      ], settings: Settings(weeklyCapacity: [0, 0, 0, 0, 0, 0, 0]));

      expect(plannedIds(p), isEmpty);
      expect(p.laterTaskIds, ['far']);
    });

    test('only an override has capacity: the deadline uses that day', () {
      final p = plan(
        [task('due-fri', 3, age: 1, due: today.addDays(4))],
        settings: Settings(weeklyCapacity: [0, 0, 0, 0, 0, 0, 0]),
        overrides: [DayOverride(date: today.addDays(2), capacity: 1)],
      );

      expect(schedule(p), {
        '2026-11-18': ['due-fri'],
      });
      expect(p.atRiskTaskIds, isEmpty);
    });
  });

  group('urgency boost', () {
    const weekdaysTwo = [2, 2, 2, 2, 2, 0, 0];
    const everyDayThree = [3, 3, 3, 3, 3, 3, 3];

    /// Worked example 2: spare capacity, one Low task due on Thursday.
    List<Task> example2() => [
      task('A', 2, age: 1),
      task('F', 2, age: 2),
      task('B', 3, age: 3),
      task('G', 3, age: 4),
      task('H', 3, age: 5),
      task('L', 4, age: 6, due: LocalDate(2026, 11, 19)),
    ];

    test('5. worked example 2: the boost moves L two days before its '
        'deadline', () {
      final p = plan(
        example2(),
        settings: Settings(weeklyCapacity: weekdaysTwo),
      );

      expect(schedule(p), {
        '2026-11-16': ['A', 'F'], // L slack 3: tier 3, behind B, G, H
        '2026-11-17': ['L', 'B'], // L slack 2: tier 2, nobody else there
        '2026-11-18': ['G', 'H'],
      });
      expect(p.days[1].entries.first.reason, PlanReason.priority);
    });

    test('5. worked example 2 with thresholds 0 / 0: L waits for the last '
        'feasible day', () {
      final p = plan(
        example2(),
        settings: noBoost.copyWith(weeklyCapacity: weekdaysTwo),
      );

      expect(schedule(p), {
        '2026-11-16': ['A', 'F'],
        '2026-11-17': ['B', 'G'],
        '2026-11-18': ['H', 'L'],
      });
    });

    test('6. worked example 1 with boost: E jumps ahead of F two days '
        'before its deadline', () {
      final p = plan(example1());

      expect(focusIds(p), ['K']);
      expect(schedule(p), {
        '2026-11-16': ['A'], // C is boosted to tier 2 but A, F are its own
        '2026-11-17': ['C'], // forced
        '2026-11-18': ['D'], // forced
        '2026-11-19': ['E'], // slack 2: Normal 3 -> 1, ahead of High F
        '2026-11-20': ['F'],
        '2026-11-21': ['K', 'B'],
      });
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('16. the boost clamps at priority 1', () {
      // High due tomorrow: 2 - 2 = 0 -> 1. It ties with Critical (and stays
      // behind it as a guest in the tier) and beats an older High task.
      final p = plan([
        task('high-plain', 2, age: 1),
        task('high-due', 2, age: 2, due: today.addDays(1)),
        task('critical', 1, age: 3),
      ], settings: Settings(weeklyCapacity: everyDayThree));

      expect(schedule(p)['2026-11-16'], ['critical', 'high-due', 'high-plain']);
    });

    test('16. Someday due tomorrow counts as Normal', () {
      // 5 - 2 = 3: behind an original Normal, ahead of a Low task.
      final p = plan([
        task('low', 4, age: 1),
        task('someday-due', 5, age: 2, due: today.addDays(1)),
        task('normal', 3, age: 3),
      ], settings: Settings(weeklyCapacity: everyDayThree));

      expect(schedule(p)['2026-11-16'], ['normal', 'someday-due', 'low']);
    });

    test('a boosted task joins a tier behind the tasks that belong there', () {
      final p = plan([
        task('low-due', 4, age: 1, due: today.addDays(2)), // 4 - 2 = 2
        task('high-new', 2, age: 9),
      ], settings: Settings(weeklyCapacity: everyDayThree));

      expect(schedule(p)['2026-11-16'], ['high-new', 'low-due']);
    });

    test('within a tier a more urgent original priority goes first', () {
      // Both land in tier 1: Normal (3 - 2) and High (2 - 1).
      final p = plan([
        task('normal-near', 3, age: 1, due: today.addDays(2)),
        task('high-soon', 2, age: 2, due: today.addDays(6)),
      ], settings: Settings(weeklyCapacity: everyDayThree));

      expect(schedule(p)['2026-11-16'], ['high-soon', 'normal-near']);
    });

    group('thresholds', () {
      /// The order in which the plan takes a Low task due in [slack] days
      /// and plain tasks of priorities 2, 3 and 4.
      List<String> orderWithSlack(int slack, {Settings? settings}) {
        final p = plan(
          [
            task('p2', 2, age: 1),
            task('p3', 3, age: 2),
            task('p4', 4, age: 3),
            task('due', 4, age: 4, due: today.addDays(slack)),
          ],
          settings: (settings ?? Settings()).copyWith(
            weeklyCapacity: [4, 4, 4, 4, 4, 4, 4],
          ),
        );
        return [for (final e in p.days.first.entries) e.taskId];
      }

      test('beyond the soon threshold there is no boost', () {
        // Priority 4 with a due date: only the due date puts it before p4.
        expect(orderWithSlack(8), ['p2', 'p3', 'due', 'p4']);
        expect(orderWithSlack(60), ['p2', 'p3', 'due', 'p4']);
      });

      test('within the soon threshold: one level', () {
        expect(orderWithSlack(7), ['p2', 'p3', 'due', 'p4']);
        expect(orderWithSlack(3), ['p2', 'p3', 'due', 'p4']);
      });

      test('within the near threshold: two levels', () {
        expect(orderWithSlack(2), ['p2', 'due', 'p3', 'p4']);
        expect(orderWithSlack(1), ['p2', 'due', 'p3', 'p4']);
      });

      test('custom thresholds move the boundaries', () {
        final wide = Settings(urgencySoonDays: 30, urgencyNearDays: 10);
        expect(orderWithSlack(10, settings: wide), ['p2', 'due', 'p3', 'p4']);
        expect(orderWithSlack(11, settings: wide), ['p2', 'p3', 'due', 'p4']);
      });
    });

    test('the boost grows as the plan moves through the days', () {
      // Capacity 1. The Low task is due in 9 days: no boost on days 0-1,
      // tier 3 from day 2 (slack 7), tier 2 from day 7 (slack 2). Tier 3
      // still holds its own Normal tasks, so the guest waits for day 7.
      final p = plan([
        for (var i = 1; i <= 9; i++) task('n$i', 3, age: i),
        task('low-due', 4, age: 20, due: today.addDays(9)),
      ], settings: Settings(weeklyCapacity: everyDayOne));

      expect(plannedIds(p).indexOf('low-due'), 7);
      expect(p.atRiskTaskIds, isEmpty);
    });

    group('steps are levels of the scale (ADR-17)', () {
      /// Today's order of a Normal task due in [slack] days among plain
      /// tasks of the given levels, on [scale].
      List<String> order(int scale, int slack, List<int> levels) {
        final p = plan(
          [
            for (final l in levels) task('l$l', 0, age: l, level: l),
            task('due', 0, age: 20, level: 5, due: today.addDays(slack)),
          ],
          settings: Settings(
            priorityScale: scale,
            weeklyCapacity: const [9, 9, 9, 9, 9, 9, 9],
          ),
        );
        return [for (final e in p.days.first.entries) e.taskId];
      }

      test('scale 10: one step is Elevated, two are High', () {
        expect(order(10, 5, [3, 4]), ['l3', 'l4', 'due']);
        expect(order(10, 2, [3, 4]), ['l3', 'due', 'l4']);
      });

      test('scale 3: one step is Critical', () {
        expect(order(3, 5, [2, 3, 4]), ['l2', 'due', 'l3', 'l4']);
      });

      test('a level the scale does not offer steps from the one it shows', () {
        // Elevated (4) shows as High on scale 5: one step is Critical.
        final p = plan([
          task('critical', 0, age: 1, level: 2),
          task('elevated-due', 0, age: 2, level: 4, due: today.addDays(5)),
          task('high', 0, age: 3, level: 3),
        ], settings: Settings(weeklyCapacity: everyDayThree));

        expect(schedule(p)['2026-11-16'], ['critical', 'elevated-due', 'high']);
      });
    });

    test('later is listed in plain priority order, without boost', () {
      final p = plan(
        [
          task('first', 1, age: 1),
          task('low-due', 4, age: 2, due: today.addDays(1)),
          task('high', 2, age: 3),
          task('normal', 3, age: 4),
        ],
        settings: Settings(weeklyCapacity: everyDayOne, planningHorizonDays: 1),
      );

      expect(plannedIds(p), ['first']);
      expect(p.laterTaskIds, ['high', 'normal', 'low-due']);
    });
  });

  group('overflow and at-risk', () {
    final wednesday = LocalDate(2026, 11, 18);

    List<Task> cluster() => [
      task('P', 4, age: 1, due: wednesday),
      task('Q', 4, age: 2, due: wednesday),
      task('R', 4, age: 3, due: wednesday),
      task('S', 4, age: 4, due: wednesday),
      task('A', 2, age: 5),
    ];

    test('7. worked example 3: a deadline cluster is spread 2/1/1', () {
      final p = plan(
        cluster(),
        settings: Settings(weeklyCapacity: everyDayOne),
      );

      expect(schedule(p), {
        '2026-11-16': ['P', 'Q'],
        '2026-11-17': ['R'],
        '2026-11-18': ['S'],
        '2026-11-19': ['A'],
      });
      final monday = p.days.first;
      expect(monday.isOverloaded, isTrue);
      expect(monday.entries[0].overflow, isFalse);
      expect(monday.entries[1].overflow, isTrue);
      expect(
        monday.entries.every((e) => e.reason == PlanReason.deadline),
        isTrue,
      );
      expect(p.days[1].isOverloaded, isFalse);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('8. worked example 3 without overflow: S lands after its due date '
        'and is at risk', () {
      final p = plan(
        cluster(),
        settings: Settings(weeklyCapacity: everyDayOne, maxOverflowPerDay: 0),
      );

      expect(schedule(p), {
        '2026-11-16': ['P'],
        '2026-11-17': ['Q'],
        '2026-11-18': ['R'],
        '2026-11-19': ['S'],
        '2026-11-20': ['A'],
      });
      expect(p.atRiskTaskIds, ['S']);
      final s = p.days[3].entries.single;
      expect(s.atRisk, isTrue);
      expect(s.overflow, isFalse);
      expect(s.reason, PlanReason.deadline);
      expect(p.days.any((d) => d.isOverloaded), isFalse);
      expect(p.days[0].entries.single.atRisk, isFalse);
    });

    test('9. two tasks due today, capacity 1, overflow 1: both today, the '
        'second is overflow', () {
      final p = plan([
        task('first', 3, age: 1, due: today),
        task('second', 3, age: 2, due: today),
      ]);

      final monday = p.days.first;
      expect([for (final e in monday.entries) e.taskId], ['first', 'second']);
      expect(monday.entries[0].overflow, isFalse);
      expect(monday.entries[1].overflow, isTrue);
      expect(monday.isOverloaded, isTrue);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('overflow is bounded: what exceeds it spills and is at risk', () {
      final p = plan([
        for (var i = 1; i <= 4; i++) task('d$i', 3, age: i, due: today),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['d1', 'd2'],
        '2026-11-17': ['d3', 'd4'],
      });
      expect(p.atRiskTaskIds, ['d3', 'd4']);
      expect(p.days[1].entries[1].overflow, isTrue);
      expect(p.days[1].entries.every((e) => e.atRisk), isTrue);
    });

    test('a higher overflow setting admits more on one day', () {
      final p = plan([
        for (var i = 1; i <= 4; i++) task('d$i', 3, age: i, due: today),
      ], settings: Settings(maxOverflowPerDay: 3));

      expect(schedule(p), {
        '2026-11-16': ['d1', 'd2', 'd3', 'd4'],
      });
      expect(
        [for (final e in p.days.first.entries) e.overflow],
        [false, true, true, true],
      );
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('priority picks never use overflow', () {
      final p = plan([for (var i = 1; i <= 5; i++) task('t$i', 1, age: i)]);

      expect(p.days.any((d) => d.isOverloaded), isFalse);
      expect(schedule(p)['2026-11-16'], ['t1']);
    });

    test('rest days take no overflow: a missed deadline waits for the next '
        'working day', () {
      // Sat 21 holds 3 + 1 overflow; Sun 22 is a rest day.
      final saturday = LocalDate(2026, 11, 21);
      final p = plan(
        [for (var i = 1; i <= 6; i++) task('d$i', 3, age: i, due: saturday)],
        overrides: [
          for (var i = 0; i < 5; i++)
            DayOverride(date: today.addDays(i), capacity: 0),
        ],
      );

      expect(schedule(p), {
        '2026-11-21': ['d1', 'd2', 'd3', 'd4'],
        '2026-11-23': ['d5', 'd6'],
      });
      expect(p.days[6].entries, isEmpty);
      expect(p.atRiskTaskIds, ['d5', 'd6']);
    });

    test('14. today\'s capacity already done: no priority picks, a forced '
        'task still appears as overflow', () {
      final p = plan([
        task('plain', 1, age: 1),
        task('due-today', 4, age: 2, due: today),
      ], completedTodayCount: 1);

      final monday = p.days.first;
      expect(monday.capacity, 0);
      expect([for (final e in monday.entries) e.taskId], ['due-today']);
      expect(monday.entries.single.overflow, isTrue);
      expect(monday.entries.single.reason, PlanReason.deadline);
      expect(schedule(p)['2026-11-17'], ['plain']);
    });

    group('deadline slots refill (D16)', () {
      final settings = Settings(weeklyCapacity: [2, 2, 2, 2, 2, 2, 2]);
      final dueToday = [
        for (var i = 1; i <= 5; i++) task('d$i', 3, age: i, due: today),
      ];

      List<String> todayIds(Plan p) => [
        for (final e in p.days.first.entries) e.taskId,
      ];

      test('capacity 2, overflow 1, five due today: three are shown and the '
          'plan is flagged as not achievable', () {
        final p = plan(dueToday, settings: settings);

        expect(todayIds(p), ['d1', 'd2', 'd3']);
        expect(p.days.first.isOverloaded, isTrue);
        expect(p.atRiskTaskIds, ['d4', 'd5']);
        expect(p.hasAtRisk, isTrue);
      });

      test('closing one pulls the next due-today task in', () {
        final p = plan(
          dueToday.sublist(1),
          settings: settings,
          completedTodayCount: 1,
        );

        expect(todayIds(p), ['d2', 'd3', 'd4']);
        expect(p.atRiskTaskIds, ['d5']);
      });

      test('it keeps refilling until every due-today task is shown', () {
        final afterTwo = plan(
          dueToday.sublist(2),
          settings: settings,
          completedTodayCount: 2,
        );
        expect(todayIds(afterTwo), ['d3', 'd4', 'd5']);
        expect(afterTwo.hasAtRisk, isFalse);

        final afterFour = plan(
          dueToday.sublist(4),
          settings: settings,
          completedTodayCount: 4,
        );
        expect(todayIds(afterFour), ['d5']);
        expect(afterFour.hasAtRisk, isFalse);
      });

      test('without overflow two are shown, three are at risk, and closing '
          'one still pulls the next', () {
        final noOverflow = settings.copyWith(maxOverflowPerDay: 0);

        final before = plan(dueToday, settings: noOverflow);
        expect(todayIds(before), ['d1', 'd2']);
        expect(before.atRiskTaskIds, ['d3', 'd4', 'd5']);
        expect(before.hasAtRisk, isTrue);

        final after = plan(
          dueToday.sublist(1),
          settings: noOverflow,
          completedTodayCount: 1,
        );
        expect(todayIds(after), ['d2', 'd3']);
        expect(after.atRiskTaskIds, ['d4', 'd5']);
      });

      test('plain tasks are still not refilled (D3)', () {
        final plain = [for (var i = 1; i <= 5; i++) task('p$i', 3, age: i)];

        final p = plan(
          plain.sublist(1),
          settings: settings,
          completedTodayCount: 1,
        );

        expect(todayIds(p), ['p2']);
        expect(p.hasAtRisk, isFalse);
      });

      test('a closed deadline slot is not refilled with a plain task', () {
        final p = plan(
          [task('due', 3, age: 1, due: today), task('plain', 1, age: 2)],
          settings: settings,
          completedTodayCount: 2,
        );

        expect(todayIds(p), ['due']);
      });
    });

    test('no day exceeds capacity + overflow and rest days stay empty', () {
      final tasks = [
        for (var i = 0; i < 60; i++)
          task('t$i', 1 + i % 5, age: i, due: today.addDays(i % 9)),
      ];
      for (final overflow in [0, 1, 2, 3]) {
        final p = plan(tasks, settings: Settings(maxOverflowPerDay: overflow));
        for (final day in p.days) {
          if (day.capacity == 0) {
            expect(day.entries, isEmpty, reason: '${day.date}');
          } else {
            expect(
              day.entries.length,
              lessThanOrEqualTo(day.capacity + overflow),
              reason: '${day.date}',
            );
          }
        }
        expect(plannedIds(p).toSet(), hasLength(60));
        expect(p.laterTaskIds, isEmpty);
      }
    });

    test('atRiskTaskIds lists exactly the entries flagged at risk', () {
      final p = plan([
        for (var i = 0; i < 30; i++)
          task('t$i', 3, age: i, due: today.addDays(i % 4)),
      ]);

      expect(p.atRiskTaskIds, isNotEmpty);
      expect(p.atRiskTaskIds, [
        for (final day in p.days)
          for (final e in day.entries)
            if (e.atRisk) e.taskId,
      ]);
    });
  });

  group('pinned tasks', () {
    Task pin(Task t, LocalDate date) => t.copyWith(pinnedDate: date);

    final settings = Settings(weeklyCapacity: everyDayOne);
    final wednesday = today.addDays(2);

    test('12. a pinned task takes its slot first', () {
      final p = plan([
        task('h1', 1, age: 1),
        task('h2', 1, age: 2),
        task('h3', 1, age: 3),
        pin(task('pinned', 5, age: 4), wednesday),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-16': ['h1'],
        '2026-11-17': ['h2'],
        '2026-11-18': ['pinned'],
        '2026-11-19': ['h3'],
      });
      final entry = p.days[2].entries.single;
      expect(entry.reason, PlanReason.pinned);
      expect(entry.overflow, isFalse);
      expect(entry.atRisk, isFalse);
    });

    test('12. a pin in the past behaves as today', () {
      final p = plan([
        task('high', 1, age: 1),
        pin(task('pinned-past', 5, age: 2), today.addDays(-3)),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-16': ['pinned-past'],
        '2026-11-17': ['high'],
      });
      expect(p.days.first.entries.single.reason, PlanReason.pinned);
      expect(p.focus, isEmpty);
    });

    test('a pinned task is not pulled earlier into free slots', () {
      final p = plan([
        pin(task('pinned', 1, age: 1), today.addDays(3)),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-19': ['pinned'],
      });
    });

    test('on its day the order is pinned, deadline, priority', () {
      final p = plan([
        task('plain', 1, age: 1),
        task('due-today', 3, age: 2, due: today),
        pin(task('pinned', 5, age: 3), today),
      ], settings: Settings(weeklyCapacity: [3, 3, 3, 3, 3, 3, 3]));

      expect(
        [for (final e in p.days.first.entries) (e.taskId, e.reason)],
        [
          ('pinned', PlanReason.pinned),
          ('due-today', PlanReason.deadline),
          ('plain', PlanReason.priority),
        ],
      );
    });

    test('several pins on one day are all kept, above capacity as '
        'overflow', () {
      final p = plan([
        pin(task('pin-low', 4, age: 1), today),
        pin(task('pin-high', 2, age: 2), today),
        pin(task('pin-mid', 3, age: 3), today),
        task('plain', 1, age: 4),
      ], settings: settings);

      final monday = p.days.first;
      expect(
        [for (final e in monday.entries) e.taskId],
        ['pin-high', 'pin-mid', 'pin-low'],
      );
      expect([for (final e in monday.entries) e.overflow], [false, true, true]);
      expect(monday.isOverloaded, isTrue);
      expect(schedule(p)['2026-11-17'], ['plain']);
    });

    test('a pin is honoured on a rest day', () {
      final sunday = LocalDate(2026, 11, 22);
      final p = plan([pin(task('pinned', 3, age: 1), sunday)]);

      expect(schedule(p), {
        '2026-11-22': ['pinned'],
      });
      final day = p.days[6];
      expect(day.capacity, 0);
      expect(day.entries.single.overflow, isTrue);
      expect(day.isOverloaded, isTrue);
    });

    test('pins use up the overflow room of deadline tasks', () {
      final p = plan([
        pin(task('pinned', 5, age: 1), today),
        task('d1', 3, age: 2, due: today),
        task('d2', 3, age: 3, due: today),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-16': ['pinned', 'd1'],
        '2026-11-17': ['d2'],
      });
      expect(p.atRiskTaskIds, ['d2']);
    });

    test('13. a pin on a future day reduces the room for deadlines', () {
      final tuesday = today.addDays(1);
      List<Task> tasks({required bool pinned}) => [
        task('high', 1, age: 1),
        task('due-tue', 5, age: 2, due: tuesday),
        pinned
            ? pin(task('other', 5, age: 3), tuesday)
            : task('other', 5, age: 3),
      ];

      // Without the pin Tuesday has room for the deadline.
      expect(schedule(plan(tasks(pinned: false), settings: settings)), {
        '2026-11-16': ['high'],
        '2026-11-17': ['due-tue'],
        '2026-11-18': ['other'],
      });

      // With Tuesday taken by the pin the deadline is forced on Monday.
      final p = plan(tasks(pinned: true), settings: settings);
      expect(schedule(p), {
        '2026-11-16': ['due-tue'],
        '2026-11-17': ['other'],
        '2026-11-18': ['high'],
      });
      expect(p.days[0].entries.single.reason, PlanReason.deadline);
      expect(p.days[1].entries.single.reason, PlanReason.pinned);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('a task pinned after its due date is at risk', () {
      final p = plan([
        pin(task('late', 3, age: 1, due: today.addDays(1)), today.addDays(3)),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-19': ['late'],
      });
      expect(p.days[3].entries.single.atRisk, isTrue);
      expect(p.atRiskTaskIds, ['late']);
    });

    test('a pin beyond the horizon is later', () {
      final p = plan([
        task('plain', 3, age: 1),
        pin(task('far', 1, age: 2), today.addDays(30)),
      ], settings: settings.copyWith(planningHorizonDays: 7));

      expect(plannedIds(p), ['plain']);
      expect(p.laterTaskIds, ['far']);
    });

    test('a pin in the past is on today\'s list, so not in the strip', () {
      final p = plan([
        pin(task('focused', 3, age: 1, focused: 1), today.addDays(-2)),
        pin(task('other', 3, age: 2, focused: 2), wednesday),
      ], settings: settings);

      expect(focusIds(p), ['focused', 'other']);
      expect(stripIds(p), ['other']);
    });
  });

  group('countCompletedToday', () {
    // Completion instants are given in local time, as the user lives them.
    Task doneAt(
      String id,
      DateTime local, {
      bool onPlan = true,
      int? focused,
    }) => task(id, 3, age: 1, focused: focused).complete(local, onPlan: onPlan);

    int count(List<Task> tasks, {int dayStartHour = 0}) =>
        Planner.countCompletedToday(
          tasks,
          today: today,
          dayStartHour: dayStartHour,
        );

    test('counts tasks completed on the planning day', () {
      expect(
        count([
          doneAt('morning', DateTime(2026, 11, 16, 0, 0, 1)),
          doneAt('evening', DateTime(2026, 11, 16, 23, 59)),
        ]),
        2,
      );
    });

    test('ignores other days and active tasks', () {
      expect(
        count([
          doneAt('yesterday', DateTime(2026, 11, 15, 23, 59)),
          doneAt('tomorrow', DateTime(2026, 11, 17, 0, 0)),
          task('active', 3, age: 1),
        ]),
        0,
      );
    });

    test('14. counts only completions from today\'s list (D19)', () {
      expect(
        count([
          doneAt('ahead', DateTime(2026, 11, 16, 10), onPlan: false),
          doneAt('planned', DateTime(2026, 11, 16, 11)),
        ]),
        1,
      );
    });

    test('the Focus mark does not matter', () {
      expect(
        count([
          doneAt('from-list', DateTime(2026, 11, 16, 10), focused: 1),
          doneAt(
            'from-strip',
            DateTime(2026, 11, 16, 11),
            onPlan: false,
            focused: 2,
          ),
        ]),
        1,
      );
    });

    test('14. a task done ahead of its day leaves today as it is; one done '
        'from today\'s list is not replaced', () {
      final settings = Settings(weeklyCapacity: [2, 2, 2, 2, 2, 2, 2]);
      final noon = DateTime(2026, 11, 16, 12);
      final tasks = [for (var i = 1; i <= 6; i++) task('t$i', 3, age: i)];
      Plan planFor(List<Task> all) => plan(
        all,
        settings: settings,
        completedTodayCount: Planner.countCompletedToday(
          all,
          today: today,
          dayStartHour: 0,
        ),
      );
      List<Task> withDone(String id, {required bool onPlan}) => [
        for (final t in tasks)
          t.id == id ? t.complete(noon, onPlan: onPlan) : t,
      ];

      expect(schedule(planFor(tasks)), {
        '2026-11-16': ['t1', 't2'],
        '2026-11-17': ['t3', 't4'],
        '2026-11-18': ['t5', 't6'],
      });
      // t4 was Tuesday's: Monday keeps both tasks, the rest moves up.
      expect(schedule(planFor(withDone('t4', onPlan: false))), {
        '2026-11-16': ['t1', 't2'],
        '2026-11-17': ['t3', 't5'],
        '2026-11-18': ['t6'],
      });
      // t1 was Monday's: its slot stays empty.
      expect(schedule(planFor(withDone('t1', onPlan: true))), {
        '2026-11-16': ['t2'],
        '2026-11-17': ['t3', 't4'],
        '2026-11-18': ['t5', 't6'],
      });
    });

    test('respects the day start hour', () {
      final tasks = [
        doneAt('before-start', DateTime(2026, 11, 16, 3, 59)), // still the 15th
        doneAt('at-start', DateTime(2026, 11, 16, 4)),
        doneAt('after-midnight', DateTime(2026, 11, 17, 2)), // still the 16th
        doneAt('next-day', DateTime(2026, 11, 17, 4)),
      ];

      expect(count(tasks, dayStartHour: 4), 2);
      expect(count(tasks), 2); // midnight: before-start and at-start
    });

    test('a task deleted after completion still counts', () {
      final done = doneAt('done', DateTime(2026, 11, 16, 10));
      expect(count([done.trash(DateTime(2026, 11, 16, 12))]), 1);
    });
  });

  group('performance', () {
    /// 500 tasks of every kind: plain, due (near, far, overdue), focused
    /// and pinned.
    List<Task> manyTasks() => [
      for (var i = 0; i < 500; i++)
        () {
          final t = task(
            't$i',
            1 + i % 5,
            age: i,
            due: i % 3 == 0 ? today.addDays(i % 120 - 5) : null,
            focused: i % 41 == 0 ? i : null,
          );
          return i % 29 == 0
              ? t.copyWith(pinnedDate: today.addDays(i % 60))
              : t;
        }(),
    ];

    test('19. 500 tasks over a 90-day horizon plan in under 50 ms', () {
      final tasks = manyTasks();
      Plan run() => plan(tasks);

      // Let the JIT warm up, then take the best of several runs so that a
      // busy CI machine does not fail the test on a single hiccup.
      for (var i = 0; i < 5; i++) {
        run();
      }
      var best = const Duration(days: 1);
      for (var i = 0; i < 10; i++) {
        final watch = Stopwatch()..start();
        run();
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }

      // ignore: avoid_print
      print('planner: 500 tasks x 90 days in ${best.inMicroseconds} us');
      expect(best.inMilliseconds, lessThan(50));
    });

    test('19. every task ends up in exactly one place', () {
      final tasks = manyTasks();
      final p = plan(tasks);

      final seen = [...plannedIds(p), ...p.laterTaskIds];
      expect(seen, hasLength(500));
      expect(seen.toSet(), {for (final t in tasks) t.id});
      // Focus is a second look at the same tasks.
      expect(seen, containsAll(focusIds(p)));
      expect(focusIds(p).toSet(), {
        for (final t in tasks)
          if (t.isFocused || (t.dueDate != null && t.dueDate! < today)) t.id,
      });
    });

    test('18. the large plan is deterministic and order-independent', () {
      final expected = plan(manyTasks());

      expect(plan(manyTasks()), expected);
      expect(plan(manyTasks().reversed.toList()), expected);
    });
  });

  group('horizon', () {
    test('17. horizon 7, 20 tasks, capacity 1: 7 planned, 13 later', () {
      final p = plan(
        [for (var i = 1; i <= 20; i++) task('t${100 + i}', 3, age: i)],
        settings: Settings(weeklyCapacity: everyDayOne, planningHorizonDays: 7),
      );

      expect(p.days, hasLength(7));
      expect(plannedIds(p), [for (var i = 1; i <= 7; i++) 't${100 + i}']);
      expect(p.laterTaskIds, [for (var i = 8; i <= 20; i++) 't${100 + i}']);
    });

    test('later keeps the pool order', () {
      final p = plan(
        [
          task('low', 5, age: 1),
          task('high', 2, age: 2),
          task('top', 1, age: 3),
        ],
        settings: Settings(weeklyCapacity: everyDayOne, planningHorizonDays: 1),
      );

      expect(plannedIds(p), ['top']);
      expect(p.laterTaskIds, ['high', 'low']);
    });
  });

  group('determinism', () {
    List<Task> mixed() => [
      for (var i = 0; i < 40; i++)
        task(
          't$i',
          1 + i % 5,
          age: i ~/ 3, // several tasks share a createdAt
          due: i % 4 == 0 ? today.addDays(i - 6) : null,
          focused: i % 7 == 0 ? i % 3 : null,
        ),
    ];

    test('18. the same input twice gives an identical plan', () {
      expect(plan(mixed()), plan(mixed()));
    });

    test('18. the order of the input list does not matter', () {
      final expected = plan(mixed());

      expect(plan(mixed().reversed.toList()), expected);
      expect(
        plan(mixed()..sort((a, b) => a.title.compareTo(b.title))),
        expected,
      );
    });

    test('the input list is not modified', () {
      final tasks = mixed();
      final before = [...tasks];
      plan(tasks);
      expect(tasks, before);
    });
  });
}
