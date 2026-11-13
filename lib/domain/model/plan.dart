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

    /// The Focus view (D17): focused and overdue tasks in focus order. It is
    /// a second look at tasks that are also in [days] or [laterTaskIds].
    @Default(<FocusEntry>[]) List<FocusEntry> focus,

    /// How many entries the Focus strip shows at once.
    required int focusVisibleLimit,

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

  /// The Focus strip of the Today screen: the first [focusVisibleLimit]
  /// focus entries that are not on today's list already.
  List<FocusEntry> get visibleFocus =>
      _focusOffToday.take(focusVisibleLimit).toList();

  /// Size of the "+N more" counter of the Focus strip.
  int get hiddenFocusCount {
    final hidden = _focusOffToday.length - focusVisibleLimit;
    return hidden > 0 ? hidden : 0;
  }

  Iterable<FocusEntry> get _focusOffToday =>
      focus.where((e) => e.plannedDate != today);
}

/// A task in the Focus view.
@freezed
abstract class FocusEntry with _$FocusEntry {
  @Assert('overdueDays >= 0', 'overdueDays must not be negative')
  const factory FocusEntry({
    required String taskId,

    /// The user set the Focus mark (otherwise the task is here as overdue).
    required bool focused,

    /// 0 when not overdue; above 0 the UI shows "overdue by N days".
    @Default(0) int overdueDays,

    /// The day the plan puts the task on; `null` when it is "later".
    LocalDate? plannedDate,
  }) = _FocusEntry;

  const FocusEntry._();

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
