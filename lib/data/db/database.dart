import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasks_order/data/db/converters.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart' show TaskStatus;

part 'database.g.dart';

/// Tasks, including done and soft-deleted ones. See docs/03 Data Model.md.
@DataClassName('TaskRow')
@TableIndex(name: 'idx_tasks_status', columns: {#status, #deletedAt})
@TableIndex(name: 'idx_tasks_due', columns: {#dueDate})
class Tasks extends Table {
  /// UUID v4.
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get priority => integer()();
  TextColumn get dueDate => text().map(const LocalDateConverter()).nullable()();
  BoolColumn get isFocused => boolean().withDefault(const Constant(false))();
  IntColumn get focusedAt =>
      integer().map(const UtcMillisConverter()).nullable()();
  TextColumn get pinnedDate =>
      text().map(const LocalDateConverter()).nullable()();
  TextColumn get notBefore =>
      text().map(const LocalDateConverter()).nullable()();

  /// 0 active, 1 done: the index of [TaskStatus], so its order must not change.
  IntColumn get status => intEnum<TaskStatus>()();
  IntColumn get createdAt => integer().map(const UtcMillisConverter())();
  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
  IntColumn get completedAt =>
      integer().map(const UtcMillisConverter()).nullable()();
  BoolColumn get completedOnPlan =>
      boolean().withDefault(const Constant(false))();

  /// Soft delete: Trash (D14) and sync tombstone (D12).
  IntColumn get deletedAt =>
      integer().map(const UtcMillisConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Planning settings: one row with `id = 1`. The column defaults repeat the
/// defaults of the domain `Settings`; the schema test keeps them equal.
@DataClassName('SettingsRow')
class SettingsTable extends Table {
  @override
  String get tableName => 'settings';

  // The self-reference is how drift spells a CHECK; drift_dev reads it from
  // the source and the getter is never called.
  IntColumn get id =>
      // ignore: recursive_getters
      integer().withDefault(const Constant(1)).check(id.equals(1))();
  IntColumn get priorityScale => integer().withDefault(const Constant(5))();

  /// JSON array, Monday first.
  TextColumn get weeklyCapacity => text()
      .map(const IntListConverter())
      .withDefault(const Constant('[1,1,1,1,1,3,0]'))();
  IntColumn get maxOverflowPerDay => integer().withDefault(const Constant(1))();
  IntColumn get planningHorizonDays =>
      integer().withDefault(const Constant(90))();
  IntColumn get urgencySoonDays => integer().withDefault(const Constant(7))();
  IntColumn get urgencyNearDays => integer().withDefault(const Constant(2))();
  IntColumn get focusVisibleLimit => integer().withDefault(const Constant(3))();
  IntColumn get dayStartHour => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Capacity for single dates; soft-deleted like tasks (D12).
@DataClassName('DayOverrideRow')
class DayOverrides extends Table {
  TextColumn get date => text().map(const LocalDateConverter())();
  IntColumn get capacity => integer()();
  TextColumn get note => text().nullable()();
  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
  IntColumn get deletedAt =>
      integer().map(const UtcMillisConverter()).nullable()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// The local store (drift / SQLite). Only `lib/data` talks to it; the rest of
/// the app sees repositories.
@DriftDatabase(tables: [Tasks, SettingsTable, DayOverrides])
class AppDatabase extends _$AppDatabase {
  /// Runs on the given executor. Tests pass an in-memory database.
  AppDatabase(super.e);

  /// The database of the app: a SQLite file in the application support
  /// directory on Android and Windows, SQLite wasm in the browser.
  AppDatabase.open() : super(_openConnection());

  /// File name on native platforms (`tasks_order.sqlite`) and storage name in
  /// the browser.
  static const databaseName = 'tasks_order';

  /// `updated_at` of the seeded settings row: the epoch, meaning "never
  /// changed by the user", so any real change wins a last-write-wins merge.
  static final DateTime seedTimestamp = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Seed the single settings row with the column defaults.
      await into(settingsTable)
          .insert(SettingsTableCompanion.insert(updatedAt: seedTimestamp));
    },
  );

  static QueryExecutor _openConnection() => driftDatabase(
    name: databaseName,
    native: const DriftNativeOptions(
      // Not the default documents directory: on Windows that is the user's
      // "Documents" folder.
      databaseDirectory: getApplicationSupportDirectory,
    ),
    // The two files are added to web/ by T-206.
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
