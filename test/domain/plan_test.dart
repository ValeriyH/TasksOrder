import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';

void main() {
  final today = LocalDate(2026, 11, 16);
  final isAssertionError = throwsA(isA<AssertionError>());

  PlanEntry entry(String id, {bool overflow = false}) =>
      PlanEntry(taskId: id, reason: PlanReason.priority, overflow: overflow);

  group('PlannedDay.isOverloaded', () {
    test('an empty day is not overloaded', () {
      expect(PlannedDay(date: today, capacity: 1).isOverloaded, isFalse);
      expect(PlannedDay(date: today, capacity: 0).isOverloaded, isFalse);
    });

    test('a day below or at capacity is not overloaded', () {
      expect(
        PlannedDay(
          date: today,
          capacity: 2,
          entries: [entry('a')],
        ).isOverloaded,
        isFalse,
      );
      expect(
        PlannedDay(
          date: today,
          capacity: 2,
          entries: [entry('a'), entry('b')],
        ).isOverloaded,
        isFalse,
      );
    });

    test('a day above capacity is overloaded', () {
      expect(
        PlannedDay(
          date: today,
          capacity: 1,
          entries: [entry('a'), entry('b', overflow: true)],
        ).isOverloaded,
        isTrue,
      );
    });

    test('any entry on a zero-capacity day overloads it', () {
      // Today's capacity drops to 0 once its planned tasks are completed;
      // a deadline can still force a task in.
      expect(
        PlannedDay(
          date: today,
          capacity: 0,
          entries: [entry('a', overflow: true)],
        ).isOverloaded,
        isTrue,
      );
    });

    test('capacity must not be negative', () {
      expect(() => PlannedDay(date: today, capacity: -1), isAssertionError);
    });
  });

  group('PlanEntry', () {
    test('flags default to false', () {
      const e = PlanEntry(taskId: 'a', reason: PlanReason.deadline);
      expect(e.overflow, isFalse);
      expect(e.atRisk, isFalse);
    });
  });

  group('TodayEntry', () {
    test('is overdue when overdueDays is above 0', () {
      expect(const TodayEntry(taskId: 'a', flagged: true).isOverdue, isFalse);
      expect(
        const TodayEntry(taskId: 'a', flagged: false, overdueDays: 2).isOverdue,
        isTrue,
      );
    });

    test('overdueDays must not be negative', () {
      expect(
        () => TodayEntry(taskId: 'a', flagged: true, overdueDays: -1),
        isAssertionError,
      );
    });
  });

  group('Plan', () {
    List<TodayEntry> queue(int n) => [
      for (var i = 0; i < n; i++) TodayEntry(taskId: 't$i', flagged: true),
    ];

    test('an empty plan has empty lists', () {
      final plan = Plan(today: today, todayVisibleLimit: 3);
      expect(plan.todayQueue, isEmpty);
      expect(plan.days, isEmpty);
      expect(plan.laterTaskIds, isEmpty);
      expect(plan.atRiskTaskIds, isEmpty);
      expect(plan.visibleToday, isEmpty);
      expect(plan.hiddenTodayCount, 0);
    });

    test('shows the first todayVisibleLimit queue entries', () {
      final plan = Plan(
        today: today,
        todayVisibleLimit: 3,
        todayQueue: queue(5),
      );
      expect(plan.visibleToday.map((e) => e.taskId), ['t0', 't1', 't2']);
      expect(plan.hiddenTodayCount, 2);
    });

    test('a queue within the limit is fully visible', () {
      final plan = Plan(
        today: today,
        todayVisibleLimit: 3,
        todayQueue: queue(3),
      );
      expect(plan.visibleToday, hasLength(3));
      expect(plan.hiddenTodayCount, 0);
    });

    test('plans with the same content are equal', () {
      Plan build() => Plan(
        today: today,
        todayVisibleLimit: 3,
        todayQueue: queue(2),
        days: [
          PlannedDay(date: today, capacity: 1, entries: [entry('a')]),
          PlannedDay(date: today.addDays(1), capacity: 1),
        ],
        laterTaskIds: ['z'],
        atRiskTaskIds: ['y'],
      );
      expect(build(), build());
      expect(build().hashCode, build().hashCode);
    });

    test('plans that differ in one entry are not equal', () {
      Plan build(String id) => Plan(
        today: today,
        todayVisibleLimit: 3,
        days: [
          PlannedDay(date: today, capacity: 1, entries: [entry(id)]),
        ],
      );
      expect(build('a'), isNot(build('b')));
    });
  });
}
