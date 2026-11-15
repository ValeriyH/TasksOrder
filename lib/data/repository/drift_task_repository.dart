import 'package:drift/drift.dart';
import 'package:tasks_order/data/db/converters.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/task_mapper.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/series.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';
import 'package:uuid/uuid.dart';

/// [TaskRepository] on the local drift database.
class DriftTaskRepository implements TaskRepository {
  DriftTaskRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Task>> watchAll() => _watch((t) => t.deletedAt.isNull());

  @override
  Stream<List<Task>> watchActive() => _watch(
    (t) => t.deletedAt.isNull() & t.status.equalsValue(TaskStatus.active),
  );

  @override
  Stream<List<Task>> watchTrash() => _watch(
    (t) => t.deletedAt.isNotNull(),
    orderBy: [(t) => OrderingTerm.desc(t.deletedAt), _byId],
  );

  @override
  Future<Task?> getById(String id) async => (await _row(id))?.toDomain();

  @override
  Future<void> upsert(Task task, DateTime now) => _db.transaction(() async {
    var stored = task.copyWith(updatedAt: now.toUtc());
    // One active instance with a rule per series (T-713): a second one
    // starts a series of its own as a new task. A new id too, not only a
    // new series: the successor id comes from the task id, so the old id
    // would give the successor of the old series again and overwrite it.
    if (stored.recurrence != null &&
        !stored.isDone &&
        !stored.isDeleted &&
        await _hasActiveInstance(stored.seriesId, except: stored.id)) {
      final id = const Uuid().v4();
      await deleteForever(stored.id);
      stored = stored.copyWith(id: id, seriesId: id);
    }
    await _db
        .into(_db.tasks)
        .insertOnConflictUpdate(
          // Nulls are written too (`toCompanion(false)`); a plain row would
          // leave a cleared due date or note as it was.
          stored.toRow().toCompanion(false),
        );
  });

  @override
  Future<void> complete(
    String id,
    DateTime now, {
    required bool onPlan,
    LocalDate? plannedDate,
    LocalDate? today,
  }) => _db.transaction(() async {
    final before = (await _row(id))?.toDomain();
    if (before == null || before.isDone) return;
    await _db
        .update(_db.tasks)
        .replace(
          before
              .complete(now, onPlan: onPlan, plannedDate: plannedDate)
              .toRow(),
        );
    await _insertSuccessor(before, now, today);
  });

  @override
  Future<void> skip(String id, DateTime now, {LocalDate? today}) =>
      _db.transaction(() async {
        final before = (await _row(id))?.toDomain();
        if (before == null || before.isDeleted || before.isDone) return;
        await _db.update(_db.tasks).replace(before.trash(now).toRow());
        await _insertSuccessor(before, now, today, skipped: true);
      });

  @override
  Future<UncompleteCheck> uncomplete(
    String id,
    DateTime now, {
    bool asOrdinary = false,
  }) => _db.transaction(() async {
    final before = (await _row(id))?.toDomain();
    if (before == null || !before.isDone) return UncompleteCheck.allowed;
    final check = Series.checkUncomplete(
      before,
      await _series(before.seriesId),
    );
    if (check == UncompleteCheck.notLast) return check;
    if (check == UncompleteCheck.successorChanged && !asOrdinary) {
      return check;
    }
    var after = before.uncomplete(now);
    if (before.recurrence != null) {
      await _removeUntouchedSuccessor(before);
      // Any other active instance of the series keeps the rule.
      if (await _hasActiveInstance(before.seriesId, except: id)) {
        after = after.clearRecurrence(now);
      }
    }
    await _db.update(_db.tasks).replace(after.toRow());
    return UncompleteCheck.allowed;
  });

  @override
  Future<void> setFocus(String id, bool value, DateTime now) =>
      _change(id, (task) => task.setFocus(value, now));

  @override
  Future<void> delete(String id, DateTime now) =>
      _change(id, (task) => task.trash(now));

  @override
  Future<void> restore(String id, DateTime now) => _db.transaction(() async {
    final before = (await _row(id))?.toDomain();
    if (before == null || !before.isDeleted) return;
    var after = before.restore(now);
    if (before.recurrence != null && !before.isDone) {
      // A skip undone: the successor it brought goes again (T-708).
      await _removeUntouchedSuccessor(before);
      if (await _hasActiveInstance(before.seriesId, except: id)) {
        after = after.clearRecurrence(now);
      }
    }
    await _db.update(_db.tasks).replace(after.toRow());
  });

  @override
  Future<void> deleteForever(String id) =>
      (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();

  @override
  Future<int> purgeDeleted(Duration olderThan, DateTime now) {
    final cutoff = const UtcMillisConverter().toSql(now.subtract(olderThan));
    return (_db.delete(
      _db.tasks,
    )..where((t) => t.deletedAt.isSmallerThanValue(cutoff))).go();
  }

  static OrderingTerm _byId($TasksTable t) => OrderingTerm.asc(t.id);

  Stream<List<Task>> _watch(
    Expression<bool> Function($TasksTable t) filter, {
    List<OrderingTerm Function($TasksTable t)>? orderBy,
  }) {
    final query = _db.select(_db.tasks)
      ..where(filter)
      ..orderBy(orderBy ?? [(t) => OrderingTerm.asc(t.createdAt), _byId]);
    return query.watch().map(
      (rows) => [for (final row in rows) row.toDomain()],
    );
  }

  /// Removes for good the successor of [task] when it is still active and
  /// untouched (`updatedAt == createdAt`): the one [complete] or [skip] made
  /// and nobody has used yet.
  Future<void> _removeUntouchedSuccessor(Task task) async {
    final successor = (await _row(task.successorId))?.toDomain();
    if (successor == null ||
        successor.isDone ||
        successor.isDeleted ||
        successor.updatedAt != successor.createdAt) {
      return;
    }
    await deleteForever(successor.id);
  }

  /// Inserts the next instance of [task] when it repeats and its series has
  /// no other active instance; part of the caller's transaction.
  Future<void> _insertSuccessor(
    Task task,
    DateTime now,
    LocalDate? today, {
    bool skipped = false,
  }) async {
    if (task.recurrence == null) return;
    if (await _hasActiveInstance(task.seriesId, except: task.id)) return;
    final day = today ?? LocalDate.fromDateTime(now.toLocal());
    await _db
        .into(_db.tasks)
        .insertOnConflictUpdate(
          task
              .successor(now: now, today: day, skipped: skipped)
              .toRow()
              .toCompanion(false),
        );
  }

  /// Whether the series has an instance other than [except] that is active,
  /// not in the Trash and carries the rule (docs/03 Data Model.md: at most
  /// one such instance per series).
  Future<bool> _hasActiveInstance(
    String? seriesId, {
    required String except,
  }) async {
    if (seriesId == null) return false;
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.seriesId.equals(seriesId) &
            t.id.equals(except).not() &
            t.status.equalsValue(TaskStatus.active) &
            t.deletedAt.isNull() &
            t.recurrence.isNotNull(),
      )
      ..limit(1);
    return (await query.getSingleOrNull()) != null;
  }

  /// The tasks of the series [seriesId] outside the Trash; none without one.
  Future<List<Task>> _series(String? seriesId) async {
    if (seriesId == null) return const [];
    final rows = await (_db.select(
      _db.tasks,
    )..where((t) => t.seriesId.equals(seriesId) & t.deletedAt.isNull())).get();
    return [for (final row in rows) row.toDomain()];
  }

  Future<TaskRow?> _row(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Applies a domain transition to the stored task. The transitions keep the
  /// invariants and bump `updatedAt`; they return the same object when there
  /// is nothing to change, and then nothing is written.
  Future<void> _change(String id, Task Function(Task task) transition) =>
      _db.transaction(() async {
        final before = (await _row(id))?.toDomain();
        if (before == null) return;
        final after = transition(before);
        if (identical(after, before)) return;
        await _db.update(_db.tasks).replace(after.toRow());
      });
}
