import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';

/// T-907: a done task stays on the day the plan had it on until that day is
/// past.
void main() {
  final today = LocalDate(2026, 11, 17);
  final thursday = LocalDate(2026, 11, 19);
  final created = DateTime(2026, 11, 1, 9);
  final now = DateTime(2026, 11, 17, 10);

  Task task() => Task.create(
    id: 'a',
    title: 'Task a',
    priority: PriorityLabels.normal,
    now: created,
  );

  bool kept(Task task, LocalDate day, {LocalDate? on, int dayStartHour = 0}) =>
      Planner.keptOnDay(
        task,
        day,
        today: on ?? today,
        dayStartHour: dayStartHour,
      );

  test('done ahead: on its day only, from now until that day ends', () {
    final done = task().complete(now, onPlan: false, plannedDate: thursday);

    expect(kept(done, thursday), isTrue);
    expect(kept(done, today), isFalse);
    expect(kept(done, thursday.addDays(1)), isFalse);
    // On Thursday itself it is still there; on Friday it is past.
    expect(kept(done, thursday, on: thursday), isTrue);
    expect(kept(done, thursday, on: thursday.addDays(1)), isFalse);
  });

  test('done from today\'s list: on today', () {
    final done = task().complete(now, onPlan: true, plannedDate: today);

    expect(kept(done, today), isTrue);
    expect(kept(done, today, on: today.addDays(1)), isFalse);
  });

  test('done while the plan had it Later: on no day', () {
    final done = task().complete(now, onPlan: false);

    expect(kept(done, today), isFalse);
    expect(kept(done, thursday), isFalse);
  });

  test('a completion of schema 3 (no plan day) from today\'s list: today', () {
    final done = task().complete(now, onPlan: true);

    expect(kept(done, today), isTrue);
    expect(kept(done, today, on: today.addDays(1)), isFalse);
    expect(task().complete(now, onPlan: false).completedOnPlan, isFalse);
    expect(kept(task().complete(now, onPlan: false), today), isFalse);
  });

  test('the day of the completion follows the day start hour (D15)', () {
    // 02:00 on Wednesday is still Tuesday with a day start at 04:00.
    final done = task().complete(DateTime(2026, 11, 18, 2), onPlan: true);

    expect(kept(done, today, dayStartHour: 4), isTrue);
    expect(kept(done, today), isFalse);
  });

  test('an active or a deleted task is never kept', () {
    expect(kept(task(), today), isFalse);
    final deleted = task()
        .complete(now, onPlan: false, plannedDate: thursday)
        .trash(now);
    expect(kept(deleted, thursday), isFalse);
  });
}
