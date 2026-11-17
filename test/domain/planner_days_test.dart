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

/// Weekdays, Monday = 0.
const _thu = 3;
const _fri = 4;
const _sat = 5;
const _sun = 6;

/// Allowed days (D23, ADR-25; T-1002). Scenario numbers refer to "Test
/// scenarios" in docs/04 Planner Algorithm.md. The week is `[1,1,1,1,1,3,0]`
/// and today is Monday 2026-11-16 unless a test says otherwise.
void main() {
  final monday = LocalDate(2026, 11, 16);
  final epoch = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 16, 9);

  Task task(
    String id, {
    Set<int>? only,
    int level = PriorityLabels.normal,
    int age = 0,
    LocalDate? due,
    LocalDate? pin,
    TaskSize size = TaskSize.normal,
  }) => Task.create(
    id: id,
    title: id,
    priority: level,
    dueDate: due,
    weight: size.weight,
    now: epoch.add(Duration(minutes: age)),
  ).copyWith(pinnedDate: pin, allowedWeekdays: only);

  Plan plan(
    List<Task> tasks, {
    Settings? settings,
    List<DayOverride> overrides = const [],
    LocalDate? today,
  }) => const Planner().plan(
    activeTasks: tasks,
    settings: settings ?? Settings(planningHorizonDays: 21),
    overrides: {for (final o in overrides) o.date: o},
    today: today ?? monday,
  );

  /// Non-empty days as `{'2026-11-16': ['a', 'b']}`.
  Map<String, List<String>> schedule(Plan plan) => {
    for (final day in plan.days)
      if (day.entries.isNotEmpty)
        day.date.toIso(): [for (final e in day.entries) e.taskId],
  };

  /// The days a task (and its ghosts) is placed on.
  List<String> daysOf(Plan plan, String id) => [
    for (final day in plan.days)
      for (final e in day.entries)
        if (e.taskId == id) day.date.toIso(),
  ];

  PlanEntry entryOf(Plan plan, String id) =>
      [for (final day in plan.days) ...day.entries]
          .firstWhere((e) => e.taskId == id);

  test('48. a task without the limit is planned as before', () {
    final tasks = [
      for (var i = 0; i < 6; i++) task('n$i', age: i),
      task('due', level: _low, age: 9, due: LocalDate(2026, 11, 18)),
    ];
    final all = {0, 1, 2, 3, 4, 5, 6};
    final lifted = [for (final t in tasks) t.setAllowedWeekdays(all, now)];

    expect(schedule(plan(lifted)), schedule(plan(tasks)));
    expect(plan(lifted).laterTaskIds, isEmpty);
  });

  test('49. a Critical task "only Sat" waits for Saturday, Low ones go '
      'ahead', () {
    final p = plan([
      task('tyres', only: {_sat}, level: _critical),
      for (var i = 1; i <= 5; i++) task('low$i', level: _low, age: i),
    ]);

    expect(schedule(p), {
      '2026-11-16': ['low1'],
      '2026-11-17': ['low2'],
      '2026-11-18': ['low3'],
      '2026-11-19': ['low4'],
      '2026-11-20': ['low5'],
      '2026-11-21': ['tyres'],
    });
    expect(entryOf(p, 'tyres').reason, PlanReason.priority);
    // A wrong day is not "waits for a day with room".
    expect(entryOf(p, 'tyres').waitsForRoom, isFalse);
    expect(entryOf(p, 'tyres').atRisk, isFalse);
    expect(p.focus, isEmpty);
    expect(p.atRiskTaskIds, isEmpty);
    expect(p.laterTaskIds, isEmpty);
  });

  group('50. a Low task "only Sat" behind tasks of a higher priority', () {
    final tasks = [
      task('tyres', only: {_sat}, level: _low),
      // Mon–Fri and the three slots of Saturday.
      for (var i = 1; i <= 8; i++) task('n$i', age: i),
    ];

    test('takes the Saturday of the next week', () {
      final p = plan(tasks);

      expect(schedule(p)['2026-11-21'], ['n6', 'n7', 'n8']);
      expect(daysOf(p, 'tyres'), ['2026-11-28']);
      expect(entryOf(p, 'tyres').waitsForRoom, isFalse);
      expect(p.focus, isEmpty);
    });

    test('is in later when the horizon ends before it', () {
      final p = plan(tasks, settings: Settings(planningHorizonDays: 7));

      expect(daysOf(p, 'tyres'), isEmpty);
      expect(p.laterTaskIds, ['tyres']);
    });
  });

  group('51. rest days stay empty (D6)', () {
    test('a Saturday with capacity 0 is passed over', () {
      final p = plan(
        [
          task('tyres', only: {_sat}),
        ],
        overrides: [DayOverride(date: LocalDate(2026, 11, 21), capacity: 0)],
      );

      expect(daysOf(p, 'tyres'), ['2026-11-28']);
    });

    test('"only Sun" in a week that rests on Sunday is in later', () {
      final p = plan([
        task('walk', only: {_sun}),
      ]);

      expect(daysOf(p, 'walk'), isEmpty);
      expect(p.laterTaskIds, ['walk']);
    });

    test('a Sunday with a capacity of its own takes it', () {
      final p = plan(
        [
          task('walk', only: {_sun}),
        ],
        overrides: [DayOverride(date: LocalDate(2026, 11, 29), capacity: 1)],
      );

      expect(daysOf(p, 'walk'), ['2026-11-29']);
    });
  });

  group('52. a pin wins', () {
    test('a pin on a day outside the set is honoured', () {
      final p = plan([
        task('tyres', only: {_sat}, pin: LocalDate(2026, 11, 18)),
      ]);

      expect(daysOf(p, 'tyres'), ['2026-11-18']);
      expect(entryOf(p, 'tyres').reason, PlanReason.pinned);
    });

    test('a pin in the past means the nearest allowed day, also a full '
        'one', () {
      final saturday = LocalDate(2026, 11, 21);
      final p = plan([
        task('tyres', only: {_sat}, pin: LocalDate(2026, 11, 11)),
        for (var i = 1; i <= 3; i++) task('p$i', age: i, pin: saturday),
      ]);

      expect(daysOf(p, 'tyres'), ['2026-11-21']);
      expect(entryOf(p, 'tyres').reason, PlanReason.pinned);
      expect(schedule(p)['2026-11-21'], hasLength(4));
      expect(schedule(p).containsKey('2026-11-16'), isFalse);
    });

    test('a pin in the past on an allowed today means today', () {
      final saturday = LocalDate(2026, 11, 21);
      final p = plan([
        task('tyres', only: {_sat}, pin: LocalDate(2026, 11, 11)),
      ], today: saturday);

      expect(daysOf(p, 'tyres'), ['2026-11-21']);
      expect(entryOf(p, 'tyres').reason, PlanReason.pinned);
    });

    test('a pin in the past of a task without the limit still means '
        'today', () {
      final p = plan([task('a', pin: LocalDate(2026, 11, 11))]);

      expect(daysOf(p, 'a'), ['2026-11-16']);
    });

    test('the pinned day counts as taken for the deadlines of others', () {
      // Capacity 1, no overflow: Saturday holds the moved pin, so the task
      // due on Saturday has to go on Friday at the latest.
      final settings = Settings(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 0],
        maxOverflowPerDay: 0,
        urgencySoonDays: 0,
        urgencyNearDays: 0,
        planningHorizonDays: 14,
      );
      final p = plan([
        task('tyres', only: {_sat}, pin: LocalDate(2026, 11, 11)),
        task('due', level: _low, age: 1, due: LocalDate(2026, 11, 21)),
        for (var i = 2; i <= 6; i++) task('n$i', age: i),
      ], settings: settings);

      expect(daysOf(p, 'tyres'), ['2026-11-21']);
      expect(daysOf(p, 'due'), ['2026-11-20']);
      expect(entryOf(p, 'due').reason, PlanReason.deadline);
      expect(p.atRiskTaskIds, isEmpty);
    });
  });

  test('53. "Thu, Fri" missed on a full Friday goes to the next Thursday', () {
    final friday = LocalDate(2026, 11, 20);
    final p = plan([
      task('papers', only: {_thu, _fri}, age: 1),
      task('urgent', level: _critical),
    ], today: friday);

    expect(schedule(p), {
      '2026-11-20': ['urgent'],
      '2026-11-26': ['papers'],
    });
    expect(p.focus, isEmpty);
    expect(p.atRiskTaskIds, isEmpty);
  });

  group('54. repeating tasks carry the set', () {
    final weekly = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.week,
      anchor: monday,
    );

    test('the instance and each ghost on the Saturday of its week', () {
      final series = task(
        'clean',
        only: {_sat},
      ).setRecurrence(weekly, today: monday, now: now);
      final p = plan([series]);

      expect(daysOf(p, 'clean'), ['2026-11-21', '2026-11-28', '2026-12-05']);
      expect(entryOf(p, 'clean').isGhost, isFalse);
      expect(p.laterTaskIds, isEmpty);
    });

    test('a ghost that meets no allowed day before the next repeat is '
        'dropped', () {
      // The Saturday of the second week is a rest day.
      final series = task(
        'clean',
        only: {_sat},
      ).setRecurrence(weekly, today: monday, now: now);
      final p = plan(
        [series],
        overrides: [DayOverride(date: LocalDate(2026, 11, 28), capacity: 0)],
      );

      expect(daysOf(p, 'clean'), ['2026-11-21', '2026-12-05']);
    });

    test('a pinned series keeps its pinned dates', () {
      final series = task(
        'gym',
        only: {_sat},
        pin: monday,
      ).setRecurrence(weekly, today: monday, now: now);
      final p = plan([series]);

      expect(daysOf(p, 'gym'), ['2026-11-16', '2026-11-23', '2026-11-30']);
    });
  });

  group('58. no allowed day before the due date', () {
    test('placed on the first allowed day after it, at risk', () {
      final p = plan([
        task('papers', only: {_sat}, due: LocalDate(2026, 11, 19)),
      ]);

      expect(daysOf(p, 'papers'), ['2026-11-21']);
      expect(entryOf(p, 'papers').atRisk, isTrue);
      expect(p.atRiskTaskIds, ['papers']);
    });
  });

  test('59. an overdue task "only Sat" is in Focus and planned for a '
      'Saturday', () {
    final p = plan([
      task('tyres', only: {_sat}, level: _low, due: LocalDate(2026, 11, 13)),
      task('n1', age: 1),
    ]);

    expect(schedule(p), {
      '2026-11-16': ['n1'],
      '2026-11-21': ['tyres'],
    });
    expect(entryOf(p, 'tyres').reason, PlanReason.priority);
    expect(entryOf(p, 'tyres').atRisk, isFalse);
    expect(p.atRiskTaskIds, isEmpty);
    expect(p.focus.single.taskId, 'tyres');
    expect(p.focus.single.overdueDays, 3);
    expect(p.focus.single.plannedDate, LocalDate(2026, 11, 21));
  });

  test('the top-level overflow passes over a task that may not take the '
      'day', () {
    // Both are Critical and large (two slots); a working day holds one slot.
    final p = plan([
      task('satOnly', only: {_sat}, level: _critical, size: TaskSize.large),
      task('any', level: _critical, size: TaskSize.large, age: 1),
    ]);

    expect(daysOf(p, 'any'), ['2026-11-16']);
    expect(entryOf(p, 'any').overflow, isTrue);
    expect(daysOf(p, 'satOnly'), ['2026-11-21']);
    expect(entryOf(p, 'satOnly').overflow, isFalse);
  });

  test('a task is placed on allowed days only, whatever the mix', () {
    final sets = <Set<int>?>[
      null,
      {_sat},
      {_thu, _fri},
      {0, 2},
      {_sun},
    ];
    final tasks = [
      for (var i = 0; i < 60; i++)
        task(
          't$i',
          only: sets[i % sets.length],
          level: [_critical, PriorityLabels.normal, _low][i % 3],
          age: i,
          due: i % 4 == 0 ? monday.addDays(3 + i % 20) : null,
        ),
    ];
    final settings = Settings(planningHorizonDays: 90);
    final p = plan(tasks, settings: settings);
    final byId = {for (final t in tasks) t.id: t};

    final placed = <String>[];
    for (final day in p.days) {
      for (final entry in day.entries) {
        expect(
          byId[entry.taskId]!.allowsDay(day.date),
          isTrue,
          reason: '${entry.taskId} on ${day.date.toIso()}',
        );
        placed.add(entry.taskId);
      }
    }
    // Every task once: on a day or in later ("only Sun" never has room).
    expect(
      [...placed, ...p.laterTaskIds]..sort(),
      [for (final t in tasks) t.id]..sort(),
    );
    expect(
      p.laterTaskIds,
      [
        for (var i = 0; i < 60; i++)
          if (i % sets.length == 4) 't$i',
      ]..sort(
        (a, b) => Planner.compareForList(byId[a]!, byId[b]!, today: monday),
      ),
    );
    expect(plan(tasks, settings: settings), p);
  });

  group('forcing counts only the allowed days (T-1003)', () {
    // No urgency boost: only forcing can put a Low task ahead.
    final calm = Settings(
      urgencySoonDays: 0,
      urgencyNearDays: 0,
      planningHorizonDays: 21,
    );
    final mon30 = LocalDate(2026, 11, 30);
    List<Task> busy(int count) => [
      for (var i = 1; i <= count; i++) task('n$i', age: i),
    ];

    test('55. forced on the last allowed day before the due date', () {
      final p = plan([
        task('tyres', only: {_sat}, level: _low, due: mon30),
        ...busy(20),
      ], settings: calm);

      // By priority only on the first Saturday: the next one still has room.
      expect(schedule(p)['2026-11-21'], ['n6', 'n7', 'n8']);
      expect(schedule(p)['2026-11-28'], ['tyres', 'n14', 'n15']);
      expect(entryOf(p, 'tyres').reason, PlanReason.deadline);
      expect(entryOf(p, 'tyres').atRisk, isFalse);
      expect(entryOf(p, 'tyres').overflow, isFalse);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('56. the last Saturday is a rest day: forced a week earlier', () {
      final p = plan(
        [
          task('tyres', only: {_sat}, level: _low, due: mon30),
          ...busy(20),
        ],
        settings: calm,
        overrides: [DayOverride(date: LocalDate(2026, 11, 28), capacity: 0)],
      );

      expect(schedule(p)['2026-11-21'], ['tyres', 'n6', 'n7']);
      expect(entryOf(p, 'tyres').reason, PlanReason.deadline);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('57. tasks that can only take Thu and Fri push the free one '
        'earlier', () {
      final friday = LocalDate(2026, 11, 20);
      final settings = Settings(
        weeklyCapacity: const [1, 1, 1, 1, 1, 1, 0],
        maxOverflowPerDay: 0,
        urgencySoonDays: 0,
        urgencyNearDays: 0,
        planningHorizonDays: 14,
      );
      final p = plan([
        task('a', only: {_thu, _fri}, level: _low, age: 1, due: friday),
        task('b', only: {_thu, _fri}, level: _low, age: 2, due: friday),
        task('free', level: _low, age: 3, due: friday),
        for (var i = 4; i <= 7; i++) task('n$i', age: i),
      ], settings: settings);

      expect(schedule(p), {
        '2026-11-16': ['n4'],
        '2026-11-17': ['n5'],
        '2026-11-18': ['free'],
        '2026-11-19': ['a'],
        '2026-11-20': ['b'],
        '2026-11-21': ['n6'],
        '2026-11-23': ['n7'],
      });
      expect(entryOf(p, 'free').reason, PlanReason.deadline);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('60. a large task counts only the Saturdays that can hold it', () {
      final sat28 = LocalDate(2026, 11, 28);
      final p = plan([
        task('L', only: {_sat}, level: _low, due: mon30, size: TaskSize.large),
        // One free slot is left on the last Saturday.
        task('p1', age: 1, pin: sat28),
        task('p2', age: 2, pin: sat28),
        for (var i = 3; i <= 10; i++) task('n$i', age: i),
      ], settings: calm);

      expect(schedule(p)['2026-11-21'], ['L', 'n8']);
      expect(entryOf(p, 'L').reason, PlanReason.deadline);
      expect(entryOf(p, 'L').atRisk, isFalse);
      expect(p.atRiskTaskIds, isEmpty);
    });

    test('a task that cannot be done today does not force another one', () {
      // "sat" has no allowed day before its date: nothing done on Thursday
      // helps it, so the task due next week stays where it was.
      final p = plan([
        task('sat', only: {_sat}, level: _low, due: LocalDate(2026, 11, 19)),
        task('next', level: _low, age: 1, due: LocalDate(2026, 11, 27)),
        for (var i = 2; i <= 13; i++) task('n$i', age: i),
      ], settings: calm);

      expect(schedule(p)['2026-11-19'], ['n5']);
      expect(schedule(p)['2026-11-21'], ['sat', 'n7', 'n8']);
      expect(daysOf(p, 'next'), ['2026-11-27']);
      expect(p.atRiskTaskIds, ['sat']);
    });

    test('a due date far away on days that never have room costs '
        'nothing', () {
      final tasks = [
        task('walk', only: {_sun}, due: LocalDate(9999, 12, 31)),
        task('n1', age: 1),
      ];
      final settings = Settings(planningHorizonDays: 90);
      var best = const Duration(days: 1);
      late Plan p;
      for (var i = 0; i < 5; i++) {
        final watch = Stopwatch()..start();
        p = plan(tasks, settings: settings);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
      }

      expect(p.laterTaskIds, ['walk']);
      expect(p.atRiskTaskIds, isEmpty);
      expect(best.inMilliseconds, lessThan(50));
    });

    test('60. determinism and performance: 500 tasks, a fifth with a set, '
        '90 days', () {
      final sets = <Set<int>>[
        {_sat},
        {_thu, _fri},
        {0, 2, 4},
        {_fri, _sat},
      ];
      final sizes = [TaskSize.small, TaskSize.normal, TaskSize.large];
      final tasks = [
        for (var i = 0; i < 500; i++)
          task(
            't$i',
            only: i % 5 == 0 ? sets[(i ~/ 5) % sets.length] : null,
            level: 1 + i % 10,
            age: i,
            size: sizes[i % 3],
            due: i % 3 == 0 ? monday.addDays(1 + (i * 7) % 120) : null,
          ),
      ];
      final settings = Settings(
        weeklyCapacity: const [3, 3, 3, 3, 3, 5, 0],
        planningHorizonDays: 90,
      );
      final first = plan(tasks, settings: settings);
      var best = const Duration(days: 1);
      for (var i = 0; i < 10; i++) {
        final watch = Stopwatch()..start();
        final again = plan(tasks, settings: settings);
        watch.stop();
        if (watch.elapsed < best) best = watch.elapsed;
        expect(again, first);
      }

      final byId = {for (final t in tasks) t.id: t};
      for (final day in first.days) {
        for (final entry in day.entries) {
          expect(byId[entry.taskId]!.allowsDay(day.date), isTrue);
        }
      }
      expect(best.inMilliseconds, lessThan(50));
    });
  });

  group('effWeight of a task with allowed days (D23)', () {
    Task large(Set<int>? only) => task('L', only: only, size: TaskSize.large);

    test('capped by the biggest of its own days', () {
      final settings = Settings();
      expect(Planner.effWeight(large(null), settings), 4);
      // Monday holds one slot, Saturday three.
      expect(Planner.effWeight(large({0}), settings), 2);
      expect(Planner.effWeight(large({0, _sat}), settings), 4);
      expect(Planner.effWeight(large({_sat}), settings), 4);
      // Only rest days: as a normal task, never 0.
      expect(Planner.effWeight(large({_sun}), settings), 2);
    });

    test('so a large task "only Mon" takes a Monday of one slot', () {
      final p = plan([
        large({0}),
      ]);

      expect(daysOf(p, 'L'), ['2026-11-16']);
      expect(entryOf(p, 'L').weight, 2);
      expect(entryOf(p, 'L').overflow, isFalse);
    });
  });
}
