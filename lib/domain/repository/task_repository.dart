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
  Future<void> upsert(Task task, DateTime now);

  /// Marks the task done. [onPlan]: it was on today's list of the plan at
  /// that moment (D19).
  Future<void> complete(String id, DateTime now, {required bool onPlan});

  /// Returns a done task to the active ones.
  Future<void> uncomplete(String id, DateTime now);

  /// Sets or clears the Focus mark (D17).
  Future<void> setFocus(String id, bool value, DateTime now);

  /// Soft delete: moves the task to the Trash (D14).
  Future<void> delete(String id, DateTime now);

  /// Takes the task back out of the Trash.
  Future<void> restore(String id, DateTime now);

  /// Removes the task for good, wherever it is. There is no way back.
  Future<void> deleteForever(String id);

  /// Gives every task, the done and the deleted ones too, the priority
  /// [remap] returns for its current one (T-406). Returns how many changed.
  Future<int> remapPriorities(int Function(int priority) remap, DateTime now);

  /// Removes for good the tasks that have been in the Trash for longer than
  /// [olderThan]. Returns how many were removed.
  Future<int> purgeDeleted(Duration olderThan, DateTime now);
}
