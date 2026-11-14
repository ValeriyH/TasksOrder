import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/backup/backup_codec.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_backup_repository.dart';
import 'package:tasks_order/data/repository/drift_day_override_repository.dart';
import 'package:tasks_order/data/repository/drift_settings_repository.dart';
import 'package:tasks_order/data/repository/drift_task_repository.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late DriftBackupRepository backups;
  late DriftTaskRepository tasks;
  late DriftSettingsRepository settings;
  late DriftDayOverrideRepository overrides;

  final t0 = DateTime.utc(2026, 11, 13, 8);
  final later = DateTime.utc(2026, 11, 14, 8);

  setUp(() {
    db = newTestDatabase();
    backups = DriftBackupRepository(db);
    tasks = DriftTaskRepository(db);
    settings = DriftSettingsRepository(db);
    overrides = DriftDayOverrideRepository(db);
  });

  tearDown(() => db.close());

  Task task(String id, {int minute = 0}) => Task.create(
    id: id,
    title: 'Task $id',
    priority: 3,
    now: t0.add(Duration(minutes: minute)),
  );

  /// Three tasks (active, done, deleted), two overrides, of which one is
  /// removed again, and settings that differ from the defaults.
  Future<void> fill() async {
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      final created = task(id, minute: i);
      await tasks.upsert(created, created.createdAt);
    }
    await tasks.complete('b', t0.add(const Duration(hours: 1)), onPlan: true);
    await tasks.delete('c', t0.add(const Duration(hours: 2)));
    await overrides.upsert(
      DayOverride(date: LocalDate(2026, 12, 25), capacity: 0, note: 'holiday'),
      t0,
    );
    await overrides.upsert(
      DayOverride(date: LocalDate(2026, 12, 26), capacity: 4),
      t0,
    );
    await overrides.remove(LocalDate(2026, 12, 26), t0);
    await settings.save(Settings(priorityScale: 10, dayStartHour: 4), t0);
  }

  test('an untouched database gives the defaults and nothing else', () async {
    final backup = await backups.read(t0);

    expect(backup.exportedAt, t0);
    expect(backup.settings, Settings());
    expect(backup.tasks, isEmpty);
    expect(backup.dayOverrides, isEmpty);
  });

  test('read takes everything, the Trash too', () async {
    await fill();

    final backup = await backups.read(later);

    expect(backup.exportedAt, later);
    expect(backup.tasks.map((t) => t.id), ['a', 'b', 'c']);
    expect(backup.tasks[1].isDone, isTrue);
    expect(backup.tasks[2].isDeleted, isTrue);
    expect(backup.taskCount, 2);
    expect(backup.settings.priorityScale, 10);
    expect(backup.settings.dayStartHour, 4);
    // The removed override is not kept.
    expect(backup.dayOverrides, [
      DayOverride(date: LocalDate(2026, 12, 25), capacity: 0, note: 'holiday'),
    ]);
  });

  test('round trip: save to a file, lose everything, restore', () async {
    await fill();
    final before = await backups.read(t0);
    final file = const BackupCodec().encode(before);

    // A fresh installation.
    await db.close();
    db = newTestDatabase();
    backups = DriftBackupRepository(db);
    await backups.replaceAll(const BackupCodec().decode(file), later);

    final after = await backups.read(t0);
    expect(after.tasks, before.tasks);
    expect(after.settings, before.settings);
    expect(after.dayOverrides, before.dayOverrides);

    // And the app sees it through the usual repositories.
    expect((await DriftTaskRepository(db).watchAll().first).map((t) => t.id), [
      'a',
      'b',
    ]);
    expect(
      (await DriftTaskRepository(db).watchTrash().first).map((t) => t.id),
      ['c'],
    );
    expect((await DriftSettingsRepository(db).watch().first).priorityScale, 10);
    expect((await DriftDayOverrideRepository(db).watchAll().first).keys, [
      LocalDate(2026, 12, 25),
    ]);
  });

  test('replaceAll removes what the backup does not hold', () async {
    await fill();
    final other = Backup(
      exportedAt: t0,
      settings: Settings(),
      tasks: [task('x')],
      dayOverrides: [DayOverride(date: LocalDate(2026, 12, 31), capacity: 2)],
    );

    await backups.replaceAll(other, later);

    final now = await backups.read(later);
    expect(now.tasks.map((t) => t.id), ['x']);
    expect(now.settings, Settings());
    expect(now.dayOverrides.map((o) => o.date), [LocalDate(2026, 12, 31)]);
    expect(await tasks.getById('a'), isNull);
    expect(await tasks.watchTrash().first, isEmpty);
  });

  test('an override removed earlier can come back from a backup', () async {
    await fill();
    final backup = Backup(
      exportedAt: t0,
      settings: Settings(),
      tasks: const [],
      dayOverrides: [DayOverride(date: LocalDate(2026, 12, 26), capacity: 7)],
    );

    await backups.replaceAll(backup, later);

    expect(
      (await overrides.watchAll().first)[LocalDate(2026, 12, 26)],
      DayOverride(date: LocalDate(2026, 12, 26), capacity: 7),
    );
  });

  test('tasks keep their timestamps', () async {
    final original = task('a')
        .complete(t0.add(const Duration(hours: 3)), onPlan: false);
    await backups.replaceAll(
      Backup(
        exportedAt: t0,
        settings: Settings(),
        tasks: [original],
        dayOverrides: const [],
      ),
      later,
    );

    expect(await tasks.getById('a'), original);
  });
}
