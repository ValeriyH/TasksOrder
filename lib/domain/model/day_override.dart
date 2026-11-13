import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tasks_order/domain/model/local_date.dart';

part 'day_override.freezed.dart';

/// Replaces the weekday capacity for one calendar [date] (holiday, sick day,
/// a free Saturday).
@freezed
abstract class DayOverride with _$DayOverride {
  @Assert('capacity >= 0', 'capacity must not be negative')
  const factory DayOverride({
    required LocalDate date,

    /// Tasks for this date; 0 makes it a rest day.
    required int capacity,

    /// Free text such as "holiday" or "trip".
    String? note,
  }) = _DayOverride;
}
