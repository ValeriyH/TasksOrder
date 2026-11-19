import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/task.dart';

/// One day of the home-screen widget (T-601): what the Today screen would
/// show on [date].
final class WidgetDay {
  const WidgetDay({
    required this.date,
    required this.titles,
    this.colors = const [],
    this.doneCount = 0,
    this.isRestDay = false,
  });

  final LocalDate date;

  /// Titles of the tasks still planned for [date], in plan order.
  final List<String> titles;

  /// The priority colour (`PriorityLabels.color`, ARGB) of each of [titles],
  /// for the dot before the title.
  final List<int> colors;

  /// Tasks of the day's list already completed; only today has any.
  final int doneCount;

  /// Nothing planned because the day has no capacity.
  final bool isRestDay;

  @override
  bool operator ==(Object other) =>
      other is WidgetDay &&
      other.date == date &&
      other.doneCount == doneCount &&
      other.isRestDay == isRestDay &&
      other.titles.length == titles.length &&
      other.colors.length == colors.length &&
      Iterable<int>.generate(titles.length)
          .every((i) => other.titles[i] == titles[i]) &&
      Iterable<int>.generate(colors.length)
          .every((i) => other.colors[i] == colors[i]);

  @override
  int get hashCode => Object.hash(
    date,
    doneCount,
    isRestDay,
    Object.hashAll(titles),
    Object.hashAll(colors),
  );

  @override
  String toString() => 'WidgetDay($date, $titles, done $doneCount)';
}

/// The first [days] days of [plan] for the home-screen widget.
///
/// The widget cannot compute the plan (D2), so the app hands it a cache of
/// the coming days and the widget picks the current one by itself; that way
/// it turns to the next day at the day start without the app. The days after
/// today are a forecast, as for the morning notification (ADR-20).
///
/// [doneToday] is the number of completions from today's list
/// (`Planner.countCompletedToday`); [scale] is the priority scale of the
/// settings, for the colours of the dots.
List<WidgetDay> widgetDays({
  required Plan plan,
  required Map<String, Task> tasksById,
  required int doneToday,
  required int scale,
  int days = 7,
}) => [
  for (final day in plan.days.take(days))
    _widgetDay(day, tasksById, day.date == plan.today ? doneToday : 0, scale),
];

WidgetDay _widgetDay(
  PlannedDay day,
  Map<String, Task> tasksById,
  int done,
  int scale,
) {
  final tasks = [for (final entry in day.entries) ?tasksById[entry.taskId]];
  final titles = [for (final task in tasks) task.title];
  return WidgetDay(
    date: day.date,
    titles: titles,
    colors: [
      for (final task in tasks) PriorityLabels.color(task.priority, scale),
    ],
    doneCount: done,
    // Today's capacity is already reduced by the completions (D19).
    isRestDay: titles.isEmpty && done == 0 && day.capacity == 0,
  );
}
