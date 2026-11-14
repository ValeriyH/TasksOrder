import 'package:drift/drift.dart';
import 'package:tasks_order/data/db/converters.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/task_mapper.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';

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
  Future<void> upsert(Task task, DateTime now) => _db
      .into(_db.tasks)
      .insertOnConflictUpdate(
        // Nulls are written too (`toCompanion(false)`); a plain row would
        // leave a cleared due date or note as it was.
        task.copyWith(updatedAt: now.toUtc()).toRow().toCompanion(false),
      );

  @override
  Future<void> complete(String id, DateTime now, {required bool onPlan}) =>
      _change(id, (task) => task.complete(now, onPlan: onPlan));

  @override
  Future<void> uncomplete(String id, DateTime now) =>
      _change(id, (task) => task.uncomplete(now));

  @override
  Future<void> setFocus(String id, bool value, DateTime now) =>
      _change(id, (task) => task.setFocus(value, now));

  @override
  Future<void> delete(String id, DateTime now) =>
      _change(id, (task) => task.trash(now));

  @override
  Future<void> restore(String id, DateTime now) =>
      _change(id, (task) => task.restore(now));

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
