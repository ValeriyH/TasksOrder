import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tasks_order/domain/model/local_date.dart';

part 'plan.freezed.dart';

/// Why a task sits on its day.
enum PlanReason {
  /// The user fixed the date.
  pinned,

  /// Forced by its due date, possibly pushing a higher priority later.
  deadline,

  /// Ordinary pick by priority.
  priority,
}

/// The planner's output: derived from tasks and settings, never stored (D2).
@freezed
abstract class Plan with _$Plan {
  const factory Plan({
    required LocalDate today,

    /// Flagged and overdue tasks in queue order (D11, D7); outside capacity.
    @Default(<TodayEntry>[]) List<TodayEntry> todayQueue,

    /// How many [todayQueue] entries the UI shows at once.
    required int todayVisibleLimit,

    /// One entry per day, from [today] to the end of the horizon.
    @Default(<PlannedDay>[]) List<PlannedDay> days,

    /// Tasks that did not fit the horizon.
    @Default(<String>[]) List<String> laterTaskIds,

    /// Tasks placed after their due date.
    @Default(<String>[]) List<String> atRiskTaskIds,
  }) = _Plan;

  const Plan._();

  /// Some deadline cannot be met with the current capacity and overflow; the
  /// UI highlights this so the user can choose what matters (D16).
  bool get hasAtRisk => atRiskTaskIds.isNotEmpty;

  /// The part of [todayQueue] shown on the Today screen.
  List<TodayEntry> get visibleToday =>
      todayQueue.take(todayVisibleLimit).toList();

  /// Size of the "+N more" counter: queued entries that are not shown yet.
  int get hiddenTodayCount => todayQueue.length > todayVisibleLimit
      ? todayQueue.length - todayVisibleLimit
      : 0;
}

/// A task in the Today queue.
@freezed
abstract class TodayEntry with _$TodayEntry {
  @Assert('overdueDays >= 0', 'overdueDays must not be negative')
  const factory TodayEntry({
    required String taskId,

    /// The user set the Today flag (otherwise the task is here as overdue).
    required bool flagged,

    /// 0 when not overdue; above 0 the UI shows "overdue by N days".
    @Default(0) int overdueDays,
  }) = _TodayEntry;

  const TodayEntry._();

  bool get isOverdue => overdueDays > 0;
}

/// One day of the plan.
@freezed
abstract class PlannedDay with _$PlannedDay {
  @Assert('capacity >= 0', 'capacity must not be negative')
  const factory PlannedDay({
    required LocalDate date,

    /// Effective capacity: override, else weekday; for today minus the
    /// planned tasks already completed.
    required int capacity,
    @Default(<PlanEntry>[]) List<PlanEntry> entries,
  }) = _PlannedDay;

  const PlannedDay._();

  /// More tasks than the user asked for (deadline overflow, D5).
  bool get isOverloaded => entries.length > capacity;
}

/// A task placed on a day.
@freezed
abstract class PlanEntry with _$PlanEntry {
  const factory PlanEntry({
    required String taskId,
    required PlanReason reason,

    /// Placed above the day's capacity.
    @Default(false) bool overflow,

    /// Placed after its due date.
    @Default(false) bool atRisk,
  }) = _PlanEntry;
}
