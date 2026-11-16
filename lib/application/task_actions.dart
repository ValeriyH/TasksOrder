import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/series.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';

part 'task_actions.g.dart';

/// What the lists do to a task, with the time taken from the app clock.
///
/// Safe to keep after the widget that read it is gone (a snackbar's "Undo").
class TaskActions {
  const TaskActions(this._repository, this._clock, this._today, this._paused);

  /// How long a deleted task stays in the Trash (D14).
  static const trashRetention = Duration(days: 30);

  final TaskRepository _repository;
  final Clock _clock;

  /// The planning day (D15), for the successor of a recurring task.
  final LocalDate? Function() _today;

  /// Ids of the tasks paused until tomorrow (T-710).
  final Set<String> Function() _paused;

  /// Creates a task with a title and a priority only (quick add).
  Future<void> add({required String title, required int priority}) {
    final now = _clock();
    return _repository.upsert(
      Task.create(title: title, priority: priority, now: now),
      now,
    );
  }

  /// [onPlan]: the task is on today's list of the plan right now (D19).
  /// [plannedDate]: the day the plan has it on, null when it is not placed
  /// (T-907); the Plan keeps the done task at the end of that day.
  ///
  /// Returns false and changes nothing when the task is paused: its series
  /// counts from completion and was already completed today (T-710).
  Future<bool> complete(
    String id, {
    required bool onPlan,
    LocalDate? plannedDate,
  }) async {
    if (_paused().contains(id)) return false;
    await _repository.complete(
      id,
      _clock(),
      onPlan: onPlan,
      plannedDate: plannedDate,
      today: _today(),
    );
    return true;
  }

  /// "Not this time" for a recurring task (D20): to the Trash, and the next
  /// instance comes.
  Future<void> skip(String id) =>
      _repository.skip(id, _clock(), today: _today());

  /// Takes a completion back; only the last one of a series (T-713). See
  /// [TaskRepository.uncomplete] for [asOrdinary] and the result.
  Future<UncompleteCheck> uncomplete(String id, {bool asOrdinary = false}) =>
      _repository.uncomplete(id, _clock(), asOrdinary: asOrdinary);

  Future<void> setFocus(String id, bool value) =>
      _repository.setFocus(id, value, _clock());

  /// Fixes the task to a day; null lets the planner place it again.
  Future<void> setPinnedDate(Task task, LocalDate? date) =>
      _repository.upsert(task.copyWith(pinnedDate: date), _clock());

  /// Keeps the task off the plan until [date] (T-909); null makes it
  /// available now. A pin before [date] goes, else the postponement would
  /// change nothing (a pin leads, T-714). A repeating task moves its start,
  /// as a save of the editor does ("Start" in docs/03 Data Model.md).
  Future<void> setNotBefore(Task task, LocalDate? date) {
    final now = _clock();
    final pin = task.pinnedDate;
    var changed = task.copyWith(
      notBefore: date,
      pinnedDate: date != null && pin != null && pin < date ? null : pin,
    );
    if (changed.recurrence case final rule?) {
      changed = changed.setRecurrence(
        rule,
        today: _today() ?? LocalDate.fromDateTime(now),
        now: now,
      );
    }
    return _repository.upsert(changed, now);
  }

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
TaskActions taskActions(Ref ref) => TaskActions(
  ref.watch(taskRepositoryProvider),
  ref.watch(clockProvider),
  () => ref.read(todayProvider).value,
  () => ref.read(pausedTaskIdsProvider),
);
