import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/series.dart';
import 'package:tasks_order/domain/model/task.dart';

/// T-713: only the last completion of a series can be taken back.
void main() {
  final today = LocalDate(2026, 11, 16);
  final t0 = DateTime.utc(2026, 11, 16, 8);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));
  final weekly = Recurrence.interval(
    every: 1,
    unit: RecurrenceUnit.week,
    anchor: today,
  );

  Task first() => Task.create(
    id: 'h',
    title: 'Haircut',
    priority: 5,
    now: t0,
  ).setRecurrence(weekly, today: today, now: t0);

  /// Completes [task] at [minutes] and returns (done task, its successor).
  (Task, Task) complete(Task task, int minutes) => (
    task.complete(at(minutes), onPlan: false),
    task.successor(now: at(minutes), today: today),
  );

  test('an ordinary task can always be taken back', () {
    final task = Task.create(
      id: 'p',
      title: 'Plain',
      priority: 5,
      now: t0,
    ).complete(at(1), onPlan: false);

    expect(Series.checkUncomplete(task, [task]), UncompleteCheck.allowed);
  });

  test('the last completion with an untouched successor is allowed', () {
    final (done, next) = complete(first(), 1);

    expect(Series.checkUncomplete(done, [done, next]), UncompleteCheck.allowed);
  });

  test('the last completion without a successor is allowed', () {
    final (done, _) = complete(first(), 1);

    expect(Series.checkUncomplete(done, [done]), UncompleteCheck.allowed);
  });

  test('an older completion is refused', () {
    final (a, s1) = complete(first(), 1);
    final (b, s2) = complete(s1, 2);
    final tasks = [a, b, s2];

    expect(Series.checkUncomplete(a, tasks), UncompleteCheck.notLast);
    expect(Series.checkUncomplete(b, tasks), UncompleteCheck.allowed);
    expect(Series.olderCompletions(tasks), {'h'});
  });

  test('an older completion whose successor was skipped is refused', () {
    final (a, s1) = complete(first(), 1);
    final skipped = s1.trash(at(2));
    final s2 = s1.successor(now: at(2), today: today);

    expect(
      Series.checkUncomplete(a, [a, skipped, s2]),
      UncompleteCheck.notLast,
    );
  });

  test('a changed successor asks first', () {
    final (done, next) = complete(first(), 1);
    final changed = next.setFocus(true, at(2));

    expect(
      Series.checkUncomplete(done, [done, changed]),
      UncompleteCheck.successorChanged,
    );
    expect(Series.olderCompletions([done, changed]), isEmpty);
  });

  test('a copy without the rule does not count as an instance', () {
    final (done, next) = complete(first(), 1);
    final ordinary = Task.create(
      id: 'o',
      title: 'Haircut',
      priority: 5,
      now: t0,
    ).copyWith(seriesId: 'h');

    expect(
      Series.checkUncomplete(done, [done, next, ordinary]),
      UncompleteCheck.allowed,
    );
  });

  test('tasks of other series and in the Trash are ignored', () {
    final (done, next) = complete(first(), 1);
    final other = Task.create(
      id: 'x',
      title: 'Gym',
      priority: 5,
      now: t0,
    ).setRecurrence(weekly, today: today, now: t0);
    final trashed = Task.create(id: 'y', title: 'Old', priority: 5, now: t0)
        .copyWith(seriesId: 'h')
        .setRecurrence(weekly, today: today, now: t0)
        .trash(at(3));

    expect(
      Series.checkUncomplete(done, [done, next, other, trashed]),
      UncompleteCheck.allowed,
    );
  });
}
