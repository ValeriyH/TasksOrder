import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/series.dart';
import 'package:tasks_order/domain/model/task.dart';

/// Storage of tasks, as the rest of the app sees it. The local store
/// implements it today; a sync engine would observe the same interface (D12).
///
/// Every write takes the current instant as `now` and stamps it on
/// `Task.updatedAt`. A write for an id that does not exist does nothing.
abstract interface class TaskRepository {
  /// Active and done tasks, without the Trash; oldest first.
  Stream<List<Task>> watchAll();

  /// Tasks still to do, without the Trash; oldest first. Input of the planner.
  Stream<List<Task>> watchActive();

  /// Soft-deleted tasks, the most recently deleted first.
  Stream<List<Task>> watchTrash();

  /// The task with this id, also when it is in the Trash (check
  /// `Task.isDeleted`); null when there is none.
  Future<Task?> getById(String id);

  /// Inserts the task or replaces the stored one with the same id.
  ///
  /// A series keeps one active instance with a rule (T-713): an active task
  /// with a rule whose series already has another one is stored as a new
  /// task (new id) of a series of its own, as when a rule is set in the
  /// editor on a copy that came back without its rule. The old id is gone.
  Future<void> upsert(Task task, DateTime now);

  /// Marks the task done. [onPlan]: it was on today's list of the plan at
  /// that moment (D19). [plannedDate]: the day the plan had it on, null when
  /// the plan had not placed it (T-907).
  ///
  /// A recurring task gets its successor in the same transaction
  /// (`Task.successor`, D20), unless its series already has another active
  /// instance. [today] is the planning day of the completion (D15); without
  /// it the calendar day of [now] is used.
  Future<void> complete(
    String id,
    DateTime now, {
    required bool onPlan,
    LocalDate? plannedDate,
    LocalDate? today,
  });

  /// "Not this time" for a recurring task: the instance goes to the Trash
  /// and the successor is inserted, as on completion (D20); for a rule from
  /// completion a skip ahead counts from the instance's date (T-712).
  Future<void> skip(String id, DateTime now, {LocalDate? today});

  /// Returns a done task to the active ones.
  ///
  /// Only the last completion of a series can come back (T-713,
  /// `Series.checkUncomplete`): an older one is refused
  /// ([UncompleteCheck.notLast]) and nothing changes. The last one takes
  /// its untouched successor away and comes back with its rule; when the
  /// successor was changed since, nothing changes
  /// ([UncompleteCheck.successorChanged]) unless [asOrdinary] is set, and
  /// then the task comes back without its rule and the successor carries the
  /// series on. Returns [UncompleteCheck.allowed] when the task came back
  /// (or there was nothing to do).
  Future<UncompleteCheck> uncomplete(
    String id,
    DateTime now, {
    bool asOrdinary = false,
  });

  /// Sets or clears the Focus mark (D17).
  Future<void> setFocus(String id, bool value, DateTime now);

  /// Soft delete: moves the task to the Trash (D14).
  Future<void> delete(String id, DateTime now);

  /// Takes the task back out of the Trash. For a recurring task the
  /// successor its skip made is removed when it is still untouched (undo of
  /// a skip); when the series has another active instance after that, the
  /// task comes back without its rule.
  Future<void> restore(String id, DateTime now);

  /// Removes the task for good, wherever it is. There is no way back.
  Future<void> deleteForever(String id);

  /// Removes for good the tasks that have been in the Trash for longer than
  /// [olderThan]. Returns how many were removed.
  Future<int> purgeDeleted(Duration olderThan, DateTime now);
}
