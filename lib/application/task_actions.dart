import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';

part 'task_actions.g.dart';

/// What the lists do to a task, with the time taken from the app clock.
///
/// Safe to keep after the widget that read it is gone (a snackbar's "Undo").
class TaskActions {
  const TaskActions(this._repository, this._clock);

  /// How long a deleted task stays in the Trash (D14).
  static const trashRetention = Duration(days: 30);

  final TaskRepository _repository;
  final Clock _clock;

  /// Creates a task with a title and a priority only (quick add).
  Future<void> add({required String title, required int priority}) {
    final now = _clock();
    return _repository.upsert(
      Task.create(title: title, priority: priority, now: now),
      now,
    );
  }

  /// [onPlan]: the task is on today's list of the plan right now (D19).
  Future<void> complete(String id, {required bool onPlan}) =>
      _repository.complete(id, _clock(), onPlan: onPlan);

  Future<void> uncomplete(String id) => _repository.uncomplete(id, _clock());

  Future<void> setFocus(String id, bool value) =>
      _repository.setFocus(id, value, _clock());

  /// Fixes the task to a day; null lets the planner place it again.
  Future<void> setPinnedDate(Task task, LocalDate? date) =>
      _repository.upsert(task.copyWith(pinnedDate: date), _clock());

  /// Moves the task to the Trash.
  Future<void> delete(String id) => _repository.delete(id, _clock());

  /// Takes the task back out of the Trash.
  Future<void> restore(String id) => _repository.restore(id, _clock());

  /// Removes the task for good.
  Future<void> deleteForever(String id) => _repository.deleteForever(id);

  /// Removes for good what has been in the Trash longer than
  /// [trashRetention]. Returns how many tasks went.
  Future<int> purgeOldTrash() =>
      _repository.purgeDeleted(trashRetention, _clock());

  /// Moves the due date; null removes it.
  Future<void> setDueDate(Task task, LocalDate? dueDate) =>
      _repository.upsert(task.copyWith(dueDate: dueDate), _clock());
}

@Riverpod(keepAlive: true)
TaskActions taskActions(Ref ref) =>
    TaskActions(ref.watch(taskRepositoryProvider), ref.watch(clockProvider));
