import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';

/// One morning notification: the tasks the plan puts on [day], shown at [at]
/// (T-501).
final class MorningDigest {
  const MorningDigest({
    required this.at,
    required this.day,
    required this.titles,
  });

  /// Local time when the notification appears.
  final DateTime at;

  /// The plan day it tells about (D15: before the day start hour it is still
  /// the previous one).
  final LocalDate day;

  /// Titles of the tasks planned for [day], in plan order; never empty.
  final List<String> titles;

  /// A stable id per day, `yyyymmdd`: rescheduling replaces the notification
  /// of the same day and leaves the one already shown alone.
  int get id => day.year * 10000 + day.month * 100 + day.day;

  @override
  bool operator ==(Object other) =>
      other is MorningDigest &&
      other.at == at &&
      other.day == day &&
      _sameList(other.titles, titles);

  @override
  int get hashCode => Object.hash(at, day, Object.hashAll(titles));

  @override
  String toString() => 'MorningDigest($at, $day, $titles)';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The morning notifications for the next [days] days, computed from [plan]
/// (D2: the plan is derived, so the notifications are rebuilt whenever the
/// plan changes and the app is running).
///
/// [minuteOfDay] is the local time of the notification, minutes after
/// midnight. A time already past [now] is skipped, and so is a day with
/// nothing planned (a rest day): there is nothing to tell. A day further than
/// the plan horizon is not known and not scheduled.
///
/// The days after today are a forecast: if today's tasks are not done they
/// move on and the forecast changes, which the next run of the app corrects.
List<MorningDigest> morningDigests({
  required Plan plan,
  required Map<String, Task> tasksById,
  required int minuteOfDay,
  required int dayStartHour,
  required DateTime now,
  int days = 7,
}) {
  final byDate = {for (final day in plan.days) day.date: day};
  final digests = <MorningDigest>[];
  for (var offset = 0; offset < days; offset++) {
    // Calendar fields, not added hours: a DST switch must not move the time.
    final at = DateTime(
      now.year,
      now.month,
      now.day + offset,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );
    if (!at.isAfter(now)) continue;
    final day = LocalDate.todayFor(at, dayStartHour);
    final planned = byDate[day];
    if (planned == null) continue;
    final titles = [
      for (final entry in planned.entries)
        if (tasksById[entry.taskId] case final task?) task.title,
    ];
    if (titles.isEmpty) continue;
    digests.add(MorningDigest(at: at, day: day, titles: titles));
  }
  return digests;
}
