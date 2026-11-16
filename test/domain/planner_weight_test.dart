import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/model/task_size.dart';
import 'package:tasks_order/domain/planner/planner.dart';

/// Levels of the table (ADR-17).
const _critical = 2;
const _low = 7;

/// Task size (D21, T-802, T-803). Scenario numbers refer to "Test scenarios" in
/// docs/04 Planner Algorithm.md. Sizes: S small (½), N normal (1), L large
/// (2). The default week is `[1,1,1,1,1,3,0]` and today is a Monday.
void main() {
  // Monday; Saturday is the 21st.
  final today = LocalDate(2026, 11, 16);
  final saturday = LocalDate(2026, 11, 21);
  final epoch = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 16, 9);
  LocalDate day(int offset) => today.addDays(offset);

  Task task(
    String id,
    TaskSize size, {
    int level = PriorityLabels.normal,
    int age = 0,
    LocalDate? due,
    LocalDate? pin,
  }) => Task.create(
    id: id,
    title: id,
    priority: level,
    dueDate: due,
    weight: size.weight,
    now: epoch.add(Duration(minutes: age)),
  ).copyWith(pinnedDate: pin);

  Plan plan(
    List<Task> tasks, {
    Settings? settings,
    List<DayOverride> overrides = const [],
    int completedTodayWeight = 0,
  }) => const Planner().plan(
    activeTasks: tasks,
    settings: settings ?? Settings(planningHorizonDays: 21),
    overrides: {for (final o in overrides) o.date: o},
    today: today,
    completedTodayWeight: completedTodayWeight,
  );

  /// Non-empty days as `{'2026-11-16': ['a', 'b']}`.
  Map<String, List<String>> schedule(Plan plan) => {
    for (final day in plan.days)
      if (day.entries.isNotEmpty)
        day.date.toIso(): [for (final e in day.entries) e.taskId],
  };

  PlanEntry entryOf(Plan plan, String id) =>
      [for (final day in plan.days) ...day.entries]
          .firstWhere((e) => e.taskId == id);

  PlannedDay dayOf(Plan plan, LocalDate date) =>
      plan.days.singleWhere((d) => d.date == date);

  group('effWeight (ADR-19)', () {
    test('the size, capped by the biggest weekday', () {
      final settings = Settings();
      expect(Planner.effWeight(task('s', TaskSize.small), settings), 1);
      expect(Planner.effWeight(task('n', TaskSize.normal), settings), 2);
      expect(Planner.effWeight(task('l', TaskSize.large), settings), 4);

      final ones = Settings(weeklyCapacity: const [1, 1, 1, 1, 1, 1, 0]);
      expect(Planner.effWeight(task('l', TaskSize.large), ones), 2);
      expect(Planner.effWeight(task('s', TaskSize.small), ones), 1);
    });

    test('a week of rest days only caps at normal, never at 0', () {
      final rest = Settings(weeklyCapacity: const [0, 0, 0, 0, 0, 0, 0]);
      expect(Planner.effWeight(task('l', TaskSize.large), rest), 2);
      expect(Planner.effWeight(task('s', TaskSize.small), rest), 1);
    });
  });

  group('first fit (T-802)', () {
    test('35. N, S, N, N, S with capacity 1: two S share a day', () {
      final settings = Settings(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 1],
        planningHorizonDays: 7,
      );
      final p = plan([
        task('n1', TaskSize.normal, age: 1),
        task('s1', TaskSize.small, age: 2),
        task('n2', TaskSize.normal, age: 3),
        task('n3', TaskSize.normal, age: 4),
        task('s2', TaskSize.small, age: 5),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-16': ['n1'],
        '2026-11-17': ['s1', 's2'],
        '2026-11-18': ['n2'],
        '2026-11-19': ['n3'],
      });
      expect(entryOf(p, 'n2').waitsForRoom, isTrue);
      // Also skipped on Tuesday for its weight, behind n2.
      expect(entryOf(p, 'n3').waitsForRoom, isTrue);
      expect(entryOf(p, 'n1').waitsForRoom, isFalse);
      expect(entryOf(p, 's2').waitsForRoom, isFalse);
      expect(dayOf(p, day(1)).load, 2);
      expect(dayOf(p, day(1)).isOverloaded, isFalse);
      expect(entryOf(p, 's1').weight, 1);
      expect(p.days.every((d) => d.entries.every((e) => !e.overflow)), isTrue);
    });

    test('36. a large task waits for Saturday, lighter ones go ahead', () {
      final p = plan([
        task('L', TaskSize.large, age: 0),
        for (var i = 1; i <= 6; i++)
          task('n$i', TaskSize.normal, level: _low, age: i),
      ]);

      expect(schedule(p), {
        '2026-11-16': ['n1'],
        '2026-11-17': ['n2'],
        '2026-11-18': ['n3'],
        '2026-11-19': ['n4'],
        '2026-11-20': ['n5'],
        '2026-11-21': ['L', 'n6'],
      });
      expect(entryOf(p, 'L').waitsForRoom, isTrue);
      expect(entryOf(p, 'L').weight, 4);
      expect(entryOf(p, 'L').overflow, isFalse);
      expect(dayOf(p, saturday).load, 6);
      expect(dayOf(p, saturday).isOverloaded, isFalse);
    });

    test('37. capacity 1 on every working day: a large task weighs one slot, '
        'a day override does not change it', () {
      final settings = Settings(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 0],
        planningHorizonDays: 7,
      );
      final p = plan(
        [task('L', TaskSize.large, age: 0), task('n', TaskSize.normal, age: 1)],
        settings: settings,
        overrides: [DayOverride(date: day(2), capacity: 3)],
      );

      expect(schedule(p), {
        '2026-11-16': ['L'],
        '2026-11-17': ['n'],
      });
      expect(entryOf(p, 'L').weight, 2);
      expect(entryOf(p, 'L').waitsForRoom, isFalse);
    });
  });

  group('stable today (T-802)', () {
    test('42. one of two S done from the list: the other stays, nothing is '
        'pulled in', () {
      final settings = Settings(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 1],
        planningHorizonDays: 7,
      );
      final done = task(
        's1',
        TaskSize.small,
        age: 1,
      ).complete(DateTime(2026, 11, 16, 12), onPlan: true);
      final rest = [
        task('s2', TaskSize.small, age: 2),
        task('n1', TaskSize.normal, age: 3),
        task('s3', TaskSize.small, level: _low, age: 4),
      ];
      final weight = Planner.completedTodayWeightOf(
        [done, ...rest],
        today: today,
        settings: settings,
      );
      expect(weight, 1);

      final p = plan(rest, settings: settings, completedTodayWeight: weight);

      // Half a slot is left: s2 keeps it; s3 is lighter than n1 but the day
      // is full once s2 is in.
      expect(schedule(p)['2026-11-16'], ['s2']);
      expect(p.days.first.capacityWeight, 1);
      expect(p.days.first.capacity, 0);
      expect(p.days.first.isOverloaded, isFalse);
    });

    test('42. the N of today done from the list: a Critical L next is not '
        'placed today', () {
      final p = plan([
        task('L', TaskSize.large, level: _critical, age: 1),
      ], completedTodayWeight: 2);

      expect(schedule(p)['2026-11-16'], isNull);
      expect(p.days.first.capacityWeight, 0);
    });

    test(
      'completedTodayWeightOf counts completions on the list by effWeight',
      () {
        final noon = DateTime(2026, 11, 16, 12);
        final tasks = [
          task('l', TaskSize.large).complete(noon, onPlan: true),
          task('s', TaskSize.small).complete(noon, onPlan: true),
          // Done ahead of its day: held no slot of today (D19).
          task('n', TaskSize.normal).complete(noon, onPlan: false),
          // Done yesterday.
          task(
            'y',
            TaskSize.normal,
          ).complete(DateTime(2026, 11, 15, 12), onPlan: true),
          task('a', TaskSize.normal),
        ];

        expect(
          Planner.completedTodayWeightOf(
            tasks,
            today: today,
            settings: Settings(),
          ),
          5,
        );
        // A large task weighs one slot where no weekday holds two.
        expect(
          Planner.completedTodayWeightOf(
            tasks,
            today: today,
            settings: Settings(weeklyCapacity: const [1, 1, 1, 1, 1, 1, 1]),
          ),
          3,
        );
      },
    );
  });

  group('pins and ghosts (T-802)', () {
    test('45. a pinned L on a day of capacity 1 overloads it; forcing sees '
        'no room there', () {
      final p = plan(
        [
          task('L', TaskSize.large, pin: day(1), age: 0),
          task('x', TaskSize.normal, due: day(1), age: 1),
          task('y', TaskSize.normal, level: _critical, age: 2),
        ],
        settings: Settings(
          planningHorizonDays: 7,
          urgencySoonDays: 0,
          urgencyNearDays: 0,
        ),
      );

      expect(schedule(p), {
        '2026-11-16': ['x'],
        '2026-11-17': ['L'],
        '2026-11-18': ['y'],
      });
      final tuesday = dayOf(p, day(1));
      expect(tuesday.load, 4);
      expect(tuesday.isOverloaded, isTrue);
      expect(entryOf(p, 'L').reason, PlanReason.pinned);
      expect(entryOf(p, 'L').overflow, isTrue);
      expect(entryOf(p, 'x').reason, PlanReason.deadline);
    });

    test('46. a weekly L series: the instance and each ghost take two slots '
        'of a Saturday', () {
      final weekly = task('w', TaskSize.large).setRecurrence(
        Recurrence.interval(every: 1, unit: RecurrenceUnit.week, anchor: today),
        today: today,
        now: now,
      );
      final p = plan([
        weekly,
        for (var i = 1; i <= 3; i++)
          task('n$i', TaskSize.normal, level: _low, age: i),
      ], settings: Settings(planningHorizonDays: 14));

      final placements = [
        for (final d in p.days)
          for (final e in d.entries)
            if (e.taskId == 'w') (d.date, e.weight, e.isGhost),
      ];
      expect(placements, [
        (saturday, 4, false),
        (saturday.addDays(7), 4, true),
      ]);
    });
  });

  group('top-level overflow (T-803)', () {
    test('38. a Critical L first in the queue takes the first day alone, '
        'above the capacity', () {
      final p = plan([
        task('L', TaskSize.large, level: _critical, age: 0),
        task('n', TaskSize.normal, level: _low, age: 1),
      ], settings: Settings(planningHorizonDays: 7));

      expect(schedule(p), {
        '2026-11-16': ['L'],
        '2026-11-17': ['n'],
      });
      final l = entryOf(p, 'L');
      expect(l.overflow, isTrue);
      expect(l.reason, PlanReason.priority);
      expect(l.weight, 4);
      expect(p.days.first.isOverloaded, isTrue);
    });

    test('39. with overflow 0 it waits for Saturday', () {
      final p = plan([
        task('L', TaskSize.large, level: _critical, age: 0),
        task('n', TaskSize.normal, level: _low, age: 1),
      ], settings: Settings(planningHorizonDays: 7, maxOverflowPerDay: 0));

      expect(schedule(p), {
        '2026-11-16': ['n'],
        '2026-11-21': ['L'],
      });
      expect(entryOf(p, 'L').overflow, isFalse);
      expect(entryOf(p, 'L').waitsForRoom, isTrue);
    });

    test('39. a High L (level 3) waits for Saturday even with overflow', () {
      final p = plan([
        task('L', TaskSize.large, level: 3, age: 0),
        task('n', TaskSize.normal, level: _low, age: 1),
      ], settings: Settings(planningHorizonDays: 7));

      expect(schedule(p), {
        '2026-11-16': ['n'],
        '2026-11-21': ['L'],
      });
    });

    test('40. a Normal L the boost raises to Critical: the rule does not '
        'apply (own priority)', () {
      final p = plan(
        [
          task('L', TaskSize.large, due: saturday, age: 0),
          for (var i = 1; i <= 5; i++)
            task('n$i', TaskSize.normal, level: _low, age: i),
        ],
        // Due in 5 days counts as near: two levels up, Critical.
        settings: Settings(
          planningHorizonDays: 7,
          urgencyNearDays: 5,
          urgencySoonDays: 7,
        ),
      );

      expect(schedule(p), {
        '2026-11-16': ['n1'],
        '2026-11-17': ['n2'],
        '2026-11-18': ['n3'],
        '2026-11-19': ['n4'],
        '2026-11-20': ['n5'],
        '2026-11-21': ['L'],
      });
      expect(entryOf(p, 'L').overflow, isFalse);
      expect(entryOf(p, 'L').atRisk, isFalse);
    });

    test('41. a Catastrophic N ahead of a Critical L: N first, the L the day '
        'after with overflow', () {
      final p = plan([
        task('L', TaskSize.large, level: _critical, age: 0),
        task('N', TaskSize.normal, level: 1, age: 1),
      ], settings: Settings(planningHorizonDays: 7));

      expect(schedule(p), {
        '2026-11-16': ['N'],
        '2026-11-17': ['L'],
      });
      expect(entryOf(p, 'L').overflow, isTrue);
    });

    test('never on a rest day, and inside the hard limit with what was done '
        'today', () {
      // Sunday is a rest day: a Critical L made on a Sunday waits.
      final sunday = const Planner().plan(
        activeTasks: [task('L', TaskSize.large, level: _critical)],
        settings: Settings(planningHorizonDays: 2),
        overrides: const {},
        today: LocalDate(2026, 11, 22),
      );
      expect(sunday.days.first.entries, isEmpty);
      expect(sunday.days[1].entries.single.taskId, 'L');

      // A normal task done from today's list: 2 + 4 > 4, not today.
      final p = plan(
        [task('L', TaskSize.large, level: _critical)],
        settings: Settings(planningHorizonDays: 7),
        completedTodayWeight: 2,
      );
      expect(schedule(p), {
        '2026-11-17': ['L'],
      });
    });
  });

  group('weighted forcing (T-803)', () {
    final noBoost = Settings(
      planningHorizonDays: 14,
      urgencySoonDays: 0,
      urgencyNearDays: 0,
    );

    test('43. an L due Wednesday: no day before it fits, forced on Monday '
        'with overflow', () {
      final p = plan([
        task('L', TaskSize.large, due: day(2), age: 0),
        task('c', TaskSize.normal, level: _critical, age: 1),
      ], settings: noBoost);

      final l = entryOf(p, 'L');
      expect(schedule(p)['2026-11-16'], ['L']);
      expect(l.reason, PlanReason.deadline);
      expect(l.overflow, isTrue);
      expect(l.atRisk, isFalse);
      expect(p.atRiskTaskIds, isEmpty);
      expect(schedule(p)['2026-11-17'], ['c']);
    });

    test('43. with overflow 0 it is at risk on Saturday', () {
      final p = plan([
        task('L', TaskSize.large, due: day(2), age: 0),
      ], settings: noBoost.copyWith(maxOverflowPerDay: 0));

      expect(schedule(p), {
        '2026-11-21': ['L'],
      });
      expect(entryOf(p, 'L').atRisk, isTrue);
      expect(p.atRiskTaskIds, ['L']);
    });

    test('43b. a Low L due next Monday is forced on Saturday, the only day '
        'before its date that fits it', () {
      final p = plan([
        task('L', TaskSize.large, level: _low, due: day(7), age: 0),
        for (var i = 1; i <= 5; i++) task('n$i', TaskSize.normal, age: i),
      ], settings: noBoost);

      expect(schedule(p), {
        '2026-11-16': ['n1'],
        '2026-11-17': ['n2'],
        '2026-11-18': ['n3'],
        '2026-11-19': ['n4'],
        '2026-11-20': ['n5'],
        '2026-11-21': ['L'],
      });
      expect(entryOf(p, 'L').reason, PlanReason.deadline);
      expect(entryOf(p, 'L').atRisk, isFalse);
    });

    test('43b. with Saturday taken by a pinned L it is forced today with '
        'overflow', () {
      final p = plan([
        task('L', TaskSize.large, level: _low, due: day(7), age: 0),
        task('P', TaskSize.large, pin: saturday, age: 0),
        for (var i = 1; i <= 5; i++) task('n$i', TaskSize.normal, age: i),
      ], settings: noBoost);

      expect(schedule(p), {
        '2026-11-16': ['L'],
        '2026-11-17': ['n1'],
        '2026-11-18': ['n2'],
        '2026-11-19': ['n3'],
        '2026-11-20': ['n4'],
        '2026-11-21': ['P', 'n5'],
      });
      final l = entryOf(p, 'L');
      expect(l.reason, PlanReason.deadline);
      expect(l.overflow, isTrue);
      expect(l.atRisk, isFalse);
    });

    test('44. two S due today next to a plain Critical N: both S today', () {
      final p = plan([
        task('s1', TaskSize.small, due: today, age: 0),
        task('s2', TaskSize.small, due: today, age: 1),
        task('c', TaskSize.normal, level: _critical, age: 2),
      ], settings: noBoost);

      expect(schedule(p), {
        '2026-11-16': ['s1', 's2'],
        '2026-11-17': ['c'],
      });
      expect(entryOf(p, 's1').reason, PlanReason.deadline);
      expect(entryOf(p, 's2').reason, PlanReason.deadline);
      expect(p.days.first.isOverloaded, isFalse);
    });

    test('a task that would pass the hard limit is skipped for a lighter '
        'one behind it', () {
      // Capacity 1, overflow 0: an L and an S both due today. The L does
      // not fit the hard limit, the S does.
      final p = plan([
        task('L', TaskSize.large, due: today, age: 0),
        task('s', TaskSize.small, due: today, age: 1),
      ], settings: noBoost.copyWith(maxOverflowPerDay: 0));

      expect(schedule(p)['2026-11-16'], ['s']);
      expect(entryOf(p, 's').reason, PlanReason.deadline);
      expect(p.atRiskTaskIds, ['L']);
    });
  });

  group('mixed weights at scale (T-802)', () {
    /// 500 tasks, a third of each size, of every kind: plain, due, pinned.
    List<Task> manyTasks() => [
      for (var i = 0; i < 500; i++)
        () {
          final t = task(
            't$i',
            TaskSize.values[i % 3],
            level: PriorityLabels.levels(5)[i % 5],
            age: i,
            due: i % 3 == 0 ? today.addDays(i % 120 - 5) : null,
          );
          return i % 29 == 0
              ? t.copyWith(pinnedDate: today.addDays(i % 60))
              : t;
        }(),
    ];

    Plan run(List<Task> tasks) =>
        plan(tasks, settings: Settings(planningHorizonDays: 90));

    test('47. the plan is deterministic and order-independent', () {
      final expected = run(manyTasks());

      expect(run(manyTasks()), expected);
      expect(run(manyTasks().reversed.toList()), expected);
    });

    test(
      '47. no day passes its hard limit except by pins; every task once',
      () {
        final tasks = manyTasks();
        final p = run(tasks);
        final settings = Settings();

        for (final d in p.days) {
          final pinned = d.entries
              .where((e) => e.reason == PlanReason.pinned)
              .fold(0, (sum, e) => sum + e.weight);
          final base = settings.weeklyCapacity[d.date.weekday];
          final hard = base == 0 ? 0 : 2 * (base + settings.maxOverflowPerDay);
          expect(
            d.load - pinned,
            lessThanOrEqualTo(hard > pinned ? hard - pinned : 0),
            reason: d.date.toIso(),
          );
        }
        final seen = [
          for (final d in p.days)
            for (final e in d.entries) e.taskId,
          ...p.laterTaskIds,
        ];
        expect(seen, hasLength(500));
        expect(seen.toSet(), {for (final t in tasks) t.id});
      },
    );

    test('47. 500 tasks of mixed sizes over 90 days in under 50 ms', () {
      final tasks = manyTasks();
      for (var i = 0; i < 5; i++) {
        run(tasks);
      }
      var best = const Duration(days: 1);
      for (var i = 0; i < 10; i++) {
        final watch = Stopwatch()..start();
        run(tasks);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }

      // ignore: avoid_print
      print('planner: 500 mixed tasks x 90 days in ${best.inMicroseconds} us');
      expect(best.inMilliseconds, lessThan(50));
    });
  });
}
