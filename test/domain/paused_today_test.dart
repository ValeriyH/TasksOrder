import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';

/// T-710: a series that counts from completion takes one completion a day.
void main() {
  final today = LocalDate(2026, 11, 15);
  final created = DateTime(2026, 11, 1, 9);
  final morning = DateTime(2026, 11, 15, 10);

  final afterDone = Recurrence.interval(
    every: 10,
    unit: RecurrenceUnit.day,
    afterDone: true,
  );
  final monthly = Recurrence.interval(
    every: 1,
    unit: RecurrenceUnit.month,
    anchor: today,
  );

  Task series(String id, Recurrence rule) => Task.create(
    id: id,
    title: 'Task $id',
    priority: PriorityLabels.normal,
    now: created,
  ).setRecurrence(rule, today: today, now: created);

  /// The task done at [at] and the successor its completion brings.
  List<Task> doneAt(Task task, DateTime at) => [
    task.complete(at, onPlan: false),
    task.successor(today: LocalDate.todayFor(at, 0), now: at),
  ];

  Set<String> paused(List<Task> tasks, {int dayStartHour = 0}) =>
      Planner.pausedToday(tasks, today: today, dayStartHour: dayStartHour);

  test('from completion: the next one waits for tomorrow', () {
    final h = series('h', afterDone);
    final tasks = doneAt(h, morning);

    expect(paused(tasks), {h.successorId});
  });

  test('by the calendar: the next one can be done ahead', () {
    final rent = series('rent', monthly);

    expect(paused(doneAt(rent, morning)), isEmpty);
  });

  test('a completion of another day does not pause', () {
    final h = series('h', afterDone);

    expect(paused(doneAt(h, DateTime(2026, 11, 14, 20))), isEmpty);
  });

  test('the day follows the day start hour (D15)', () {
    final h = series('h', afterDone);
    // 02:00 on the 16th is still the 15th when the day starts at 04:00.
    final tasks = doneAt(h, DateTime(2026, 11, 16, 2));

    expect(paused(tasks, dayStartHour: 4), {h.successorId});
  });

  test('other series and ordinary tasks are not paused', () {
    final h = series('h', afterDone);
    final other = series('o', afterDone);
    final plain = Task.create(
      id: 'p',
      title: 'Plain',
      priority: PriorityLabels.normal,
      now: created,
    );

    expect(paused([...doneAt(h, morning), other, plain]), {h.successorId});
  });

  test('undone again: nothing is paused', () {
    final h = series('h', afterDone);

    expect(paused([h]), isEmpty);
  });
}
