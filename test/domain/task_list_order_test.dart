import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';

void main() {
  final today = LocalDate(2026, 11, 13);

  Task task(String id, int priority, {LocalDate? due, int minute = 0}) =>
      Task.create(
        id: id,
        title: id,
        priority: priority,
        dueDate: due,
        now: DateTime(2026, 11, 1, 9, minute),
      );

  List<String> sorted(List<Task> tasks) => [
    for (final t in [
      ...tasks,
    ]..sort((a, b) => Planner.compareForList(a, b, today: today)))
      t.id,
  ];

  test('priority first, 1 is the highest', () {
    expect(sorted([task('low', 4), task('high', 1), task('mid', 2)]), [
      'high',
      'mid',
      'low',
    ]);
  });

  test('inside a priority: earlier due date first, no date last', () {
    expect(
      sorted([
        task('none', 2),
        task('late', 2, due: LocalDate(2026, 12, 1)),
        task('soon', 2, due: LocalDate(2026, 11, 14)),
      ]),
      ['soon', 'late', 'none'],
    );
  });

  test('an overdue task counts as a task without a date (D18)', () {
    expect(
      sorted([
        task('overdue', 2, due: LocalDate(2026, 11, 10)),
        task('dated', 2, due: LocalDate(2026, 11, 20), minute: 1),
        task('none', 2, minute: 2),
      ]),
      ['dated', 'overdue', 'none'],
    );
  });

  test('then the older task, then the id', () {
    expect(
      sorted([
        task('b', 3, minute: 5),
        task('c', 3, minute: 1),
        task('a', 3, minute: 5),
      ]),
      ['c', 'a', 'b'],
    );
  });

  test('a due date does not beat a higher priority', () {
    expect(sorted([task('due', 3, due: today), task('plain', 2)]), [
      'plain',
      'due',
    ]);
  });
}
