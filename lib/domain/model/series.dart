import 'package:tasks_order/domain/model/task.dart';

/// Whether a done task may be taken back (T-713).
enum UncompleteCheck {
  /// It may: an ordinary task, or the last completion of its series with an
  /// untouched successor (or none).
  allowed,

  /// An older completion of a series: a later instance of the series was
  /// completed too, or the series goes on with another active instance.
  /// Taking it back would give the series a second rule (the "four extra
  /// Haircuts" of T-713), so it is refused.
  notLast,

  /// The last completion, but its successor was changed since it came: the
  /// task can come back only as an ordinary one (without the rule), and the
  /// successor carries the series on. The UI asks first.
  successorChanged,
}

/// Rules over the instances of a series (D20) that need more than one task.
abstract final class Series {
  /// Whether [task] may be taken back, given [tasks]: any tasks that hold
  /// the other instances of its series (tasks in the Trash are ignored).
  ///
  /// A repeat may come back with its rule only while the series has no
  /// other active instance, so only the last completion of a series can be
  /// taken back: its successor ([Task.successorId]) is not done and no other
  /// instance of the series is active with a rule.
  static UncompleteCheck checkUncomplete(Task task, Iterable<Task> tasks) {
    final seriesId = task.seriesId;
    if (!task.isDone || task.recurrence == null || seriesId == null) {
      return UncompleteCheck.allowed;
    }
    final successorId = task.successorId;
    Task? successor;
    for (final other in tasks) {
      if (other.seriesId != seriesId || other.isDeleted) continue;
      if (other.id == task.id) continue;
      if (other.id == successorId) {
        successor = other;
        continue;
      }
      if (!other.isDone && other.recurrence != null) {
        return UncompleteCheck.notLast;
      }
    }
    if (successor == null) return UncompleteCheck.allowed;
    if (successor.isDone) return UncompleteCheck.notLast;
    return successor.updatedAt == successor.createdAt
        ? UncompleteCheck.allowed
        : UncompleteCheck.successorChanged;
  }

  /// The done tasks among [tasks] that cannot be taken back because they are
  /// not the last completion of their series (T-713): their Completed
  /// button is dimmed and explains why.
  static Set<String> olderCompletions(Iterable<Task> tasks) {
    final bySeries = <String, List<Task>>{};
    for (final task in tasks) {
      final seriesId = task.seriesId;
      if (seriesId == null || task.isDeleted) continue;
      (bySeries[seriesId] ??= []).add(task);
    }
    return {
      for (final series in bySeries.values)
        for (final task in series)
          if (task.isDone &&
              checkUncomplete(task, series) == UncompleteCheck.notLast)
            task.id,
    };
  }
}
