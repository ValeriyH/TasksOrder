import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';

/// Answers "how many tasks does the user want on this day?".
class CapacityResolver {
  const CapacityResolver(this.settings, [this.overrides = const {}]);

  final Settings settings;

  /// Overrides keyed by their date.
  final Map<LocalDate, DayOverride> overrides;

  /// The override for [date] when there is one, otherwise the capacity of its
  /// weekday. 0 means a rest day.
  int capacityFor(LocalDate date) =>
      overrides[date]?.capacity ?? settings.weeklyCapacity[date.weekday];
}
