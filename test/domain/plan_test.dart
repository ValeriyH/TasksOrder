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

  group('FocusEntry', () {
    test('is overdue when overdueDays is above 0', () {
      expect(const FocusEntry(taskId: 'a', focused: true).isOverdue, isFalse);
      expect(
        const FocusEntry(taskId: 'a', focused: false, overdueDays: 2).isOverdue,
        isTrue,
      );
    });

    test('overdueDays must not be negative', () {
      expect(
        () => FocusEntry(taskId: 'a', focused: true, overdueDays: -1),
        isAssertionError,
      );
    });

    test('has no planned date unless one is given', () {
      expect(const FocusEntry(taskId: 'a', focused: true).plannedDate, isNull);
    });
  });

  group('Plan', () {
    /// [n] focus entries planned for the days after today.
    List<FocusEntry> focus(int n) => [
      for (var i = 0; i < n; i++)
        FocusEntry(
          taskId: 't$i',
          focused: true,
          plannedDate: today.addDays(i + 1),
        ),
    ];

    test('an empty plan has empty lists', () {
      final plan = Plan(today: today, focusVisibleLimit: 3);
      expect(plan.focus, isEmpty);
      expect(plan.days, isEmpty);
      expect(plan.laterTaskIds, isEmpty);
      expect(plan.atRiskTaskIds, isEmpty);
      expect(plan.visibleFocus, isEmpty);
      expect(plan.hiddenFocusCount, 0);
    });

    test('the strip shows the first focusVisibleLimit entries', () {
      final plan = Plan(today: today, focusVisibleLimit: 3, focus: focus(5));
      expect(plan.visibleFocus.map((e) => e.taskId), ['t0', 't1', 't2']);
      expect(plan.hiddenFocusCount, 2);
    });

    test('entries within the limit are all visible', () {
      final plan = Plan(today: today, focusVisibleLimit: 3, focus: focus(3));
      expect(plan.visibleFocus, hasLength(3));
      expect(plan.hiddenFocusCount, 0);
    });

    test('the strip skips entries that are on the list of today', () {
      final plan = Plan(
        today: today,
        focusVisibleLimit: 2,
        focus: [
          FocusEntry(taskId: 'on-today', focused: true, plannedDate: today),
          ...focus(2),
          const FocusEntry(taskId: 'later', focused: false, overdueDays: 4),
        ],
      );
      expect(plan.focus, hasLength(4));
      expect(plan.visibleFocus.map((e) => e.taskId), ['t0', 't1']);
      expect(plan.hiddenFocusCount, 1); // 'later'; 'on-today' is not counted
    });

    test('plans with the same content are equal', () {
      Plan build() => Plan(
        today: today,
        focusVisibleLimit: 3,
        focus: focus(2),
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
        focusVisibleLimit: 3,
        days: [
          PlannedDay(date: today, capacity: 1, entries: [entry(id)]),
        ],
      );
      expect(build('a'), isNot(build('b')));
    });
  });
}
