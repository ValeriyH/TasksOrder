import 'package:drift/drift.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_settings_repository.dart';
import 'package:tasks_order/data/repository/task_mapper.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/repository/backup_repository.dart';

/// [BackupRepository] on the local drift database.
class DriftBackupRepository implements BackupRepository {
  DriftBackupRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Backup> read(DateTime now) => _db.transaction(() async {
    final tasks =
        await (_db.select(_db.tasks)..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    // Removed overrides are tombstones for sync only: not worth keeping.
    final overrides =
        await (_db.select(_db.dayOverrides)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.date)]))
            .get();
    return Backup(
      exportedAt: now.toUtc(),
      settings: await DriftSettingsRepository(_db).watch().first,
      tasks: [for (final row in tasks) row.toDomain()],
      dayOverrides: [
        for (final row in overrides)
          DayOverride(date: row.date, capacity: row.capacity, note: row.note),
      ],
    );
  });

  @override
  Future<void> replaceAll(Backup backup, DateTime now) =>
      _db.transaction(() async {
        await _db.delete(_db.tasks).go();
        await _db.delete(_db.dayOverrides).go();
        for (final task in backup.tasks) {
          await _db.into(_db.tasks).insert(task.toRow());
        }
        for (final override in backup.dayOverrides) {
          await _db
              .into(_db.dayOverrides)
              .insert(
                DayOverrideRow(
                  date: override.date,
                  capacity: override.capacity,
                  note: override.note,
                  updatedAt: now,
                ),
              );
        }
        await DriftSettingsRepository(_db).save(backup.settings, now);
      });
}
