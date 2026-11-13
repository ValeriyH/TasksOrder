import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';

part 'settings.freezed.dart';

/// Planning settings (a single row; would sync per user, D12). Device
/// settings such as language and theme live elsewhere.
///
/// `Settings()` gives the defaults from docs/03 Data Model.md. Out-of-range
/// values fail an assertion.
@freezed
abstract class Settings with _$Settings {
  @Assert(
    'PriorityLabels.scales.contains(priorityScale)',
    'priorityScale must be 3, 5 or 10',
  )
  @Assert(
    'weeklyCapacity.length == 7 && weeklyCapacity.every((c) => c >= 0)',
    'weeklyCapacity needs 7 non-negative values, Monday first',
  )
  @Assert(
    'maxOverflowPerDay >= 0 && maxOverflowPerDay <= Settings.maxOverflowLimit',
    'maxOverflowPerDay must be in 0..3',
  )
  @Assert(
    'planningHorizonDays >= 1',
    'planningHorizonDays must be at least 1 (today)',
  )
  @Assert(
    'urgencyNearDays >= 0 && urgencyNearDays <= urgencySoonDays',
    'urgency thresholds must satisfy 0 <= near <= soon',
  )
  @Assert('todayVisibleLimit >= 1', 'todayVisibleLimit must be at least 1')
  @Assert(
    'dayStartHour >= 0 && dayStartHour <= 23',
    'dayStartHour must be in 0..23',
  )
  // Not const: the capacity assertion calls a method.
  factory Settings({
    /// Lowest priority value: 3, 5 or 10 (D1).
    @Default(5) int priorityScale,

    /// Tasks per weekday, Monday first; 0 = rest day (D6).
    @Default([1, 1, 1, 1, 1, 3, 0]) List<int> weeklyCapacity,

    /// Extra tasks a deadline may add to a day (D5). The UI offers 1..3;
    /// 0 switches overflow off.
    @Default(1) int maxOverflowPerDay,

    /// Number of days the planner fills, today included; tasks that do not
    /// fit are "Later".
    @Default(90) int planningHorizonDays,

    /// Due within this many days: one priority level higher (D10).
    @Default(7) int urgencySoonDays,

    /// Due within this many days: two priority levels higher (D10).
    @Default(2) int urgencyNearDays,

    /// How many Today-queue tasks are shown at once (D11).
    @Default(3) int todayVisibleLimit,

    /// Hour at which "today" rolls over; 0 = midnight (D15).
    @Default(0) int dayStartHour,
  }) = _Settings;

  const Settings._();

  /// Upper bound of [maxOverflowPerDay].
  static const maxOverflowLimit = 3;
}
