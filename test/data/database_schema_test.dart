import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart' show TaskStatus;

import 'test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = newTestDatabase());
  tearDown(() => db.close());

  /// Column name → `TYPE`, `TYPE NOT NULL` as SQLite reports it.
  Future<Map<String, String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return {
      for (final row in rows)
        row.read<String>('name'):
            row.read<String>('type') +
            (row.read<int>('notnull') == 1 ? ' NOT NULL' : ''),
    };
  }

  TasksCompanion taskRow({String id = 'a'}) => TasksCompanion.insert(
    id: id,
    title: 'Pay the bill',
    priority: 2,
    status: TaskStatus.active,
    createdAt: DateTime.utc(2026, 11, 13, 8),
    updatedAt: DateTime.utc(2026, 11, 13, 8),
  );

  test('schema version is 1', () {
    expect(db.schemaVersion, 1);
  });

  group('columns match docs/03 Data Model.md', () {
    test('tasks', () async {
      expect(await columnsOf('tasks'), {
        'id': 'TEXT NOT NULL',
        'title': 'TEXT NOT NULL',
        'notes': 'TEXT',
        'priority': 'INTEGER NOT NULL',
        'due_date': 'TEXT',
        'is_focused': 'INTEGER NOT NULL',
        'focused_at': 'INTEGER',
        'pinned_date': 'TEXT',
        'not_before': 'TEXT',
        'status': 'INTEGER NOT NULL',
        'created_at': 'INTEGER NOT NULL',
        'updated_at': 'INTEGER NOT NULL',
        'completed_at': 'INTEGER',
        'completed_on_plan': 'INTEGER NOT NULL',
        'deleted_at': 'INTEGER',
      });
    });

    test('settings', () async {
      expect(await columnsOf('settings'), {
        'id': 'INTEGER NOT NULL',
        'priority_scale': 'INTEGER NOT NULL',
        'weekly_capacity': 'TEXT NOT NULL',
        'max_overflow_per_day': 'INTEGER NOT NULL',
        'planning_horizon_days': 'INTEGER NOT NULL',
        'urgency_soon_days': 'INTEGER NOT NULL',
        'urgency_near_days': 'INTEGER NOT NULL',
        'focus_visible_limit': 'INTEGER NOT NULL',
        'day_start_hour': 'INTEGER NOT NULL',
        'updated_at': 'INTEGER NOT NULL',
      });
    });

    test('day_overrides', () async {
      expect(await columnsOf('day_overrides'), {
        'date': 'TEXT NOT NULL',
        'capacity': 'INTEGER NOT NULL',
        'note': 'TEXT',
        'updated_at': 'INTEGER NOT NULL',
        'deleted_at': 'INTEGER',
      });
    });

    test('indexes on tasks', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'tasks' AND name LIKE 'idx_%' ORDER BY name",
          )
          .get();
      expect(rows.map((row) => row.read<String>('name')), [
        'idx_tasks_due',
        'idx_tasks_status',
      ]);
    });
  });

  group('settings row', () {
    test('is seeded on create with the domain defaults', () async {
      final row = await db.select(db.settingsTable).getSingle();
      final defaults = Settings();

      expect(row.id, 1);
      expect(row.priorityScale, defaults.priorityScale);
      expect(row.weeklyCapacity, defaults.weeklyCapacity);
      expect(row.maxOverflowPerDay, defaults.maxOverflowPerDay);
      expect(row.planningHorizonDays, defaults.planningHorizonDays);
      expect(row.urgencySoonDays, defaults.urgencySoonDays);
      expect(row.urgencyNearDays, defaults.urgencyNearDays);
      expect(row.focusVisibleLimit, defaults.focusVisibleLimit);
      expect(row.dayStartHour, defaults.dayStartHour);
      expect(row.updatedAt, AppDatabase.seedTimestamp);
    });

    test('a second row is rejected', () async {
      final second = SettingsTableCompanion.insert(
        id: const Value(2),
        updatedAt: AppDatabase.seedTimestamp,
      );
      await expectLater(
        db.into(db.settingsTable).insert(second),
        throwsA(anything),
      );
      expect(await db.select(db.settingsTable).get(), hasLength(1));
    });
  });

  group('tasks', () {
    test('a minimal row gets the defaults', () async {
      await db.into(db.tasks).insert(taskRow());
      final row = await db.select(db.tasks).getSingle();

      expect(row.isFocused, isFalse);
      expect(row.completedOnPlan, isFalse);
      expect(row.status, TaskStatus.active);
      expect(row.notes, isNull);
      expect(row.dueDate, isNull);
      expect(row.focusedAt, isNull);
      expect(row.pinnedDate, isNull);
      expect(row.notBefore, isNull);
      expect(row.completedAt, isNull);
      expect(row.deletedAt, isNull);
    });

    test('a full row is read back as written', () async {
      final at = DateTime.utc(2026, 11, 13, 9, 15, 30, 250);
      final written = TaskRow(
        id: 'b',
        title: 'File the report',
        notes: 'with the appendix',
        priority: 1,
        dueDate: LocalDate(2026, 11, 20),
        isFocused: true,
        focusedAt: at,
        pinnedDate: LocalDate(2026, 11, 18),
        notBefore: LocalDate(2026, 11, 14),
        status: TaskStatus.done,
        createdAt: at,
        updatedAt: at,
        completedAt: at,
        completedOnPlan: true,
        deletedAt: at,
      );
      await db.into(db.tasks).insert(written);

      expect(await db.select(db.tasks).getSingle(), written);
    });

    test('dates are ISO text and instants are epoch milliseconds', () async {
      final at = DateTime.utc(2026, 11, 13, 8);
      await db
          .into(db.tasks)
          .insert(
            taskRow().copyWith(
              dueDate: Value(LocalDate(2026, 11, 20)),
              status: const Value(TaskStatus.done),
              completedAt: Value(at),
            ),
          );
      final raw = await db
          .customSelect(
            'SELECT due_date, status, created_at, completed_at FROM tasks',
          )
          .getSingle();

      expect(raw.data, {
        'due_date': '2026-11-20',
        'status': 1,
        'created_at': at.millisecondsSinceEpoch,
        'completed_at': at.millisecondsSinceEpoch,
      });
    });

    test('the id is unique', () async {
      await db.into(db.tasks).insert(taskRow());
      await expectLater(db.into(db.tasks).insert(taskRow()), throwsA(anything));
    });
  });

  test('a day override is keyed by its date', () async {
    final date = LocalDate(2026, 12, 25);
    final at = DateTime.utc(2026, 11, 13, 8);
    await db
        .into(db.dayOverrides)
        .insert(
          DayOverridesCompanion.insert(
            date: date,
            capacity: 0,
            note: const Value('holiday'),
            updatedAt: at,
          ),
        );
    await db
        .into(db.dayOverrides)
        .insertOnConflictUpdate(
          DayOverridesCompanion.insert(date: date, capacity: 2, updatedAt: at),
        );

    final row = await db.select(db.dayOverrides).getSingle();
    expect(row.date, date);
    expect(row.capacity, 2);
    expect(row.deletedAt, isNull);
  });
}
