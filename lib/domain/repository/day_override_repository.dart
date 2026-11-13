import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';

/// Storage of capacity overrides for single dates.
abstract interface class DayOverrideRepository {
  /// The overrides keyed by their date, as the planner takes them.
  Stream<Map<LocalDate, DayOverride>> watchAll();

  /// Stores the override, replacing the one for the same date.
  Future<void> upsert(DayOverride override, DateTime now);

  /// Removes the override for [date], so the weekday capacity applies again.
  /// A soft delete: the record stays as a tombstone for sync (D12).
  Future<void> remove(LocalDate date, DateTime now);
}
