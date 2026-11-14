import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/notification/morning_digest.dart';

void main() {
  final today = LocalDate(2026, 11, 13);
  final created = DateTime(2026, 11, 1, 9);

  Task task(String id) => Task.create(
    id: id,
    title: 'Task $id',
    priority: PriorityLabels.normal,
    now: created,
  );

  final tasks = {
    for (final id in ['a', 'b', 'c', 'd']) id: task(id),
  };

  PlannedDay day(int offset, List<String> ids) => PlannedDay(
    date: today.addDays(offset),
    capacity: ids.length,
    entries: [
      for (final id in ids) PlanEntry(taskId: id, reason: PlanReason.priority),
    ],
  );

  final plan = Plan(
    today: today,
    focusVisibleLimit: 3,
    days: [
      day(0, ['a', 'b']),
      day(1, ['c']),
      day(2, []), // a rest day
      day(3, ['d']),
    ],
  );

  List<MorningDigest> digests({
    required DateTime now,
    int minuteOfDay = 8 * 60,
    int dayStartHour = 0,
  }) => morningDigests(
    plan: plan,
    tasksById: tasks,
    minuteOfDay: minuteOfDay,
    dayStartHour: dayStartHour,
    now: now,
  );

  test('before the time, today comes first with its titles in plan order', () {
    final result = digests(now: DateTime(2026, 11, 13, 7));

    expect(
      result.first,
      MorningDigest(
        at: DateTime(2026, 11, 13, 8),
        day: today,
        titles: const ['Task a', 'Task b'],
      ),
    );
  });

  test('after the time, today is left out', () {
    final result = digests(now: DateTime(2026, 11, 13, 10));

    expect(result.map((d) => d.day), [today.addDays(1), today.addDays(3)]);
  });

  test('rest days and days beyond the plan get nothing', () {
    final result = digests(now: DateTime(2026, 11, 13, 7));

    // Days 0, 1 and 3; day 2 is empty, days 4..6 are not in the plan.
    expect(result.map((d) => d.day), [
      today,
      today.addDays(1),
      today.addDays(3),
    ]);
    expect(result.map((d) => d.at), [
      DateTime(2026, 11, 13, 8),
      DateTime(2026, 11, 14, 8),
      DateTime(2026, 11, 16, 8),
    ]);
  });

  test('a time before the day start tells about the previous plan day', () {
    // Day starts at 04:00, notification at 03:30: on the 14th at 03:30 it is
    // still the 13th (D15).
    final result = digests(
      now: DateTime(2026, 11, 13, 10),
      minuteOfDay: 3 * 60 + 30,
      dayStartHour: 4,
    );

    expect(result.first.at, DateTime(2026, 11, 14, 3, 30));
    expect(result.first.day, today);
    expect(result.first.titles, ['Task a', 'Task b']);
  });

  test('the id is the date of the plan day', () {
    final result = digests(now: DateTime(2026, 11, 13, 7));

    expect(result.map((d) => d.id), [20261113, 20261114, 20261116]);
  });

  test('a task missing from the map is skipped', () {
    final result = morningDigests(
      plan: plan,
      tasksById: {'a': tasks['a']!},
      minuteOfDay: 8 * 60,
      dayStartHour: 0,
      now: DateTime(2026, 11, 13, 7),
    );

    expect(result.single.titles, ['Task a']);
  });
}
