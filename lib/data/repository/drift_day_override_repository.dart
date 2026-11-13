import 'package:drift/drift.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/repository/day_override_repository.dart';

/// [DayOverrideRepository] on the local drift database.
class DriftDayOverrideRepository implements DayOverrideRepository {
  DriftDayOverrideRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<Map<LocalDate, DayOverride>> watchAll() =>
      (_db.select(
        _db.dayOverrides,
      )..where((t) => t.deletedAt.isNull())).watch().map(
        (rows) => {
          for (final row in rows)
            row.date: DayOverride(
              date: row.date,
              capacity: row.capacity,
              note: row.note,
            ),
        },
      );

  @override
  Future<void> upsert(DayOverride override, DateTime now) => _db
      .into(_db.dayOverrides)
      .insertOnConflictUpdate(
        // Nulls are written too (`toCompanion(false)`): a note that was
        // cleared goes away and an override removed earlier comes back.
        DayOverrideRow(
          date: override.date,
          capacity: override.capacity,
          note: override.note,
          updatedAt: now,
        ).toCompanion(false),
      );

  @override
  Future<void> remove(LocalDate date, DateTime now) =>
      (_db.update(
        _db.dayOverrides,
      )..where((t) => t.date.equalsValue(date) & t.deletedAt.isNull())).write(
        DayOverridesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
}
