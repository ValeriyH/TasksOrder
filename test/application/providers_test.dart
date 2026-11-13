import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';

import '../data/test_database.dart';

void main() {
  // A Friday, 10:00 local time. Default capacity: Friday 1, Saturday 3,
  // Sunday 0.
  final friday = LocalDate(2026, 11, 13);
  final saturday = LocalDate(2026, 11, 14);
  late DateTime now;

  late AppDatabase db;
  late ProviderContainer container;
  late TaskRepository tasks;

  setUp(() {
    now = DateTime(2026, 11, 13, 10);
    db = newTestDatabase();
    container = ProviderContainer.test(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(db.close);
    // Keeps the plan and its inputs subscribed, as a screen would.
    container.listen(planProvider, (_, _) {});
    tasks = container.read(taskRepositoryProvider);
  });

  /// The plan after the database streams have delivered.
  Future<Plan> plan() async {
    await pumpEventQueue();
    return container.read(planProvider).requireValue;
  }

  Future<void> add(String id, {int priority = 2, LocalDate? dueDate}) =>
      tasks.upsert(
        Task.create(
          id: id,
          title: 'Task $id',
          priority: priority,
          dueDate: dueDate,
          now: now,
        ),
        now,
      );

  List<String> idsOn(Plan plan, LocalDate date) => [
    for (final day in plan.days)
      if (day.date == date)
        for (final entry in day.entries) entry.taskId,
  ];

  test('the plan is loading until the database has answered', () async {
    expect(container.read(planProvider).isLoading, isTrue);
    expect(container.read(planProvider).hasValue, isFalse);

    await pumpEventQueue();
    expect(container.read(planProvider).hasValue, isTrue);
  });

  test('an empty database gives an empty plan with the defaults', () async {
    final result = await plan();

    expect(result.today, friday);
    expect(result.days, hasLength(Settings().planningHorizonDays));
    expect(result.days.first.capacity, 1);
    expect(result.days.every((day) => day.entries.isEmpty), isTrue);
    expect(result.laterTaskIds, isEmpty);
  });

  test('a new task appears in the plan', () async {
    await plan();
    await add('a');

    expect(idsOn(await plan(), friday), ['a']);
  });

  test('tasks are planned by priority over the days', () async {
    await add('low', priority: 3);
    await add('high', priority: 1);

    final result = await plan();
    expect(idsOn(result, friday), ['high']);
    expect(idsOn(result, saturday), ['low']);
  });

  test('done and deleted tasks are not planned', () async {
    await add('done', priority: 1);
    await add('trashed', priority: 1);
    await add('left', priority: 3);
    await tasks.complete('done', now, onPlan: false);
    await tasks.delete('trashed', now);

    final result = await plan();
    expect(idsOn(result, friday), ['left']);
    expect(await container.read(allTasksProvider.future), hasLength(2));
    expect(container.read(activeTasksProvider).requireValue.single.id, 'left');
  });

  group('completing a task (D19)', () {
    setUp(() async {
      await add('first', priority: 1);
      await add('second', priority: 2);
      expect(idsOn(await plan(), friday), ['first']);
    });

    test('from the list of today: the slot is not refilled', () async {
      await tasks.complete('first', now, onPlan: true);

      final result = await plan();
      expect(idsOn(result, friday), isEmpty);
      expect(idsOn(result, saturday), ['second']);
    });

    test('from anywhere else: the list of today stays', () async {
      await tasks.complete('second', now, onPlan: false);

      expect(idsOn(await plan(), friday), ['first']);
    });

    test('undo gives the slot back', () async {
      await tasks.complete('first', now, onPlan: true);
      await plan();
      await tasks.uncomplete('first', now);

      expect(idsOn(await plan(), friday), ['first']);
    });

    test('a completion of yesterday does not count today', () async {
      final yesterday = now.subtract(const Duration(days: 1));
      await tasks.complete('first', yesterday, onPlan: true);

      expect(idsOn(await plan(), friday), ['second']);
    });
  });

  test('a settings change recomputes the plan', () async {
    await add('a', priority: 1);
    await add('b', priority: 2);
    expect(idsOn(await plan(), friday), ['a']);

    await container
        .read(settingsRepositoryProvider)
        .save(Settings(weeklyCapacity: const [2, 2, 2, 2, 2, 2, 2]), now);

    final result = await plan();
    expect(result.days.first.capacity, 2);
    expect(idsOn(result, friday), ['a', 'b']);
  });

  test('a day override changes the capacity of its date', () async {
    await add('a', priority: 1);
    await add('b', priority: 2);
    final overrides = container.read(dayOverrideRepositoryProvider);

    await overrides.upsert(DayOverride(date: friday, capacity: 0), now);
    var result = await plan();
    expect(idsOn(result, friday), isEmpty);
    expect(idsOn(result, saturday), ['a', 'b']);

    await overrides.remove(friday, now);
    result = await plan();
    expect(idsOn(result, friday), ['a']);
  });

  group('today respects dayStartHour (D15)', () {
    test('before the day start it is still yesterday', () async {
      now = DateTime(2026, 11, 14, 2);
      await container
          .read(settingsRepositoryProvider)
          .save(Settings(dayStartHour: 4), now);

      expect((await plan()).today, friday);
      expect(container.read(todayProvider).requireValue, friday);
    });

    test('a completion after midnight counts for the same day', () async {
      await container
          .read(settingsRepositoryProvider)
          .save(Settings(dayStartHour: 4), now);
      await add('first', priority: 1);
      await add('second', priority: 2);
      expect(idsOn(await plan(), friday), ['first']);

      // 01:30 on Saturday by the calendar, still Friday for the user.
      final late = DateTime(2026, 11, 14, 1, 30);
      await tasks.complete('first', late, onPlan: true);

      expect(idsOn(await plan(), friday), isEmpty);
    });
  });
}
