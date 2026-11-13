import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/repository/settings_repository.dart';

/// [SettingsRepository] on the local drift database: the row with `id = 1`.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  static const _rowId = 1;

  final AppDatabase _db;

  @override
  Stream<Settings> watch() =>
      (_db.select(_db.settingsTable)..where((t) => t.id.equals(_rowId)))
          .watchSingleOrNull()
          .map((row) => row == null ? Settings() : _toDomain(row));

  @override
  Future<void> save(Settings settings, DateTime now) => _db
      .into(_db.settingsTable)
      .insertOnConflictUpdate(
        SettingsRow(
          id: _rowId,
          priorityScale: settings.priorityScale,
          weeklyCapacity: settings.weeklyCapacity,
          maxOverflowPerDay: settings.maxOverflowPerDay,
          planningHorizonDays: settings.planningHorizonDays,
          urgencySoonDays: settings.urgencySoonDays,
          urgencyNearDays: settings.urgencyNearDays,
          focusVisibleLimit: settings.focusVisibleLimit,
          dayStartHour: settings.dayStartHour,
          updatedAt: now,
        ),
      );

  static Settings _toDomain(SettingsRow row) => Settings(
    priorityScale: row.priorityScale,
    weeklyCapacity: row.weeklyCapacity,
    maxOverflowPerDay: row.maxOverflowPerDay,
    planningHorizonDays: row.planningHorizonDays,
    urgencySoonDays: row.urgencySoonDays,
    urgencyNearDays: row.urgencyNearDays,
    focusVisibleLimit: row.focusVisibleLimit,
    dayStartHour: row.dayStartHour,
  );
}
