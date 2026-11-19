import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/widget/widget_days.dart';

void main() {
  final today = LocalDate(2026, 11, 13);

  Task task(String id) => Task.create(
    id: id,
    title: 'Task $id',
    priority: PriorityLabels.normal,
    now: DateTime(2026, 11, 1, 9),
  );

  final tasks = {
    for (final id in ['a', 'b', 'c']) id: task(id),
  };

  PlannedDay day(int offset, int capacity, List<String> ids) => PlannedDay(
    date: today.addDays(offset),
    capacity: capacity,
    entries: [
      for (final id in ids) PlanEntry(taskId: id, reason: PlanReason.priority),
    ],
  );

  Plan plan(List<PlannedDay> days) =>
      Plan(today: today, focusVisibleLimit: 3, days: days);

  test('each day of the plan with its titles in plan order', () {
    final result = widgetDays(
      plan: plan([
        day(0, 2, ['a', 'b']),
        day(1, 1, ['c']),
      ]),
      tasksById: tasks,
      doneToday: 0,
      scale: 5,
    );

    final normal = PriorityLabels.color(PriorityLabels.normal, 5);
    expect(result, [
      WidgetDay(
        date: today,
        titles: const ['Task a', 'Task b'],
        colors: [normal, normal],
      ),
      WidgetDay(
        date: today.addDays(1),
        titles: const ['Task c'],
        colors: [normal],
      ),
    ]);
  });

  test('each title has the colour of its priority on the scale', () {
    final critical = Task.create(
      id: 'x',
      title: 'Critical',
      priority: 2,
      now: DateTime(2026, 11, 1, 9),
    );
    for (final scale in [3, 5, 10]) {
      final result = widgetDays(
        plan: plan([
          day(0, 2, ['x', 'a']),
        ]),
        tasksById: {...tasks, 'x': critical},
        doneToday: 0,
        scale: scale,
      );

      expect(result.first.colors, [
        PriorityLabels.color(2, scale),
        PriorityLabels.color(PriorityLabels.normal, scale),
      ], reason: 'scale $scale');
    }
    expect(
      PriorityLabels.color(2, 5),
      isNot(PriorityLabels.color(PriorityLabels.normal, 5)),
    );
  });

  test('the completions count for today only', () {
    final result = widgetDays(
      plan: plan([
        day(0, 1, ['a']),
        day(1, 1, ['b']),
      ]),
      tasksById: tasks,
      doneToday: 2,
      scale: 5,
    );

    expect(result.map((d) => d.doneCount), [2, 0]);
  });

  test('a day without capacity is a rest day, a day all done is not', () {
    final result = widgetDays(
      plan: plan([
        // Today's capacity went to 0 because both tasks were completed.
        day(0, 0, []),
        day(1, 0, []),
        day(2, 2, []),
      ]),
      tasksById: tasks,
      doneToday: 2,
      scale: 5,
    );

    expect(result.map((d) => d.isRestDay), [false, true, false]);
  });

  test('at most [days] days', () {
    final result = widgetDays(
      plan: plan([for (var i = 0; i < 10; i++) day(i, 1, [])]),
      tasksById: tasks,
      doneToday: 0,
      scale: 5,
    );

    expect(result, hasLength(7));
  });
}
