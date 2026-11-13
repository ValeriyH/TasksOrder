import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_settings_repository.dart';
import 'package:tasks_order/domain/model/settings.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late DriftSettingsRepository repo;

  final t1 = DateTime.utc(2026, 11, 13, 8);

  final custom = Settings(
    priorityScale: 10,
    weeklyCapacity: const [2, 2, 2, 2, 2, 0, 0],
    maxOverflowPerDay: 3,
    planningHorizonDays: 30,
    urgencySoonDays: 5,
    urgencyNearDays: 1,
    focusVisibleLimit: 5,
    dayStartHour: 4,
  );

  setUp(() {
    db = newTestDatabase();
    repo = DriftSettingsRepository(db);
  });
  tearDown(() => db.close());

  test('a fresh database gives the defaults', () async {
    expect(await repo.watch().first, Settings());
  });

  test('saved settings are read back with every field', () async {
    await repo.save(custom, t1);

    expect(await repo.watch().first, custom);
  });

  test('save keeps a single row and stamps updated_at', () async {
    await repo.save(custom, t1);
    await repo.save(Settings(dayStartHour: 5), t1);

    final row = await db.select(db.settingsTable).getSingle();
    expect(row.id, 1);
    expect(row.dayStartHour, 5);
    expect(row.updatedAt, t1);
  });

  test('defaults when the row is missing; save creates it again', () async {
    await db.delete(db.settingsTable).go();
    expect(await repo.watch().first, Settings());

    await repo.save(custom, t1);
    expect(await repo.watch().first, custom);
  });

  test('the stream emits on each save', () async {
    final seen = <Settings>[];
    final subscription = repo.watch().listen(seen.add);
    await pumpEventQueue();
    await repo.save(custom, t1);
    await pumpEventQueue();
    await repo.save(Settings(), t1);
    await pumpEventQueue();
    await subscription.cancel();

    expect(seen, [Settings(), custom, Settings()]);
  });
}
