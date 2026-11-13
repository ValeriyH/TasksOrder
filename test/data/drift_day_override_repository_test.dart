import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_day_override_repository.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late DriftDayOverrideRepository repo;

  final t0 = DateTime.utc(2026, 11, 13, 8);
  final t1 = t0.add(const Duration(minutes: 1));
  final t2 = t0.add(const Duration(minutes: 2));

  final christmas = LocalDate(2026, 12, 25);
  final saturday = LocalDate(2026, 11, 14);
  final holiday = DayOverride(date: christmas, capacity: 0, note: 'holiday');
  final busy = DayOverride(date: saturday, capacity: 5);

  setUp(() {
    db = newTestDatabase();
    repo = DriftDayOverrideRepository(db);
  });
  tearDown(() => db.close());

  test('a fresh database has no overrides', () async {
    expect(await repo.watchAll().first, isEmpty);
  });

  test('overrides are read back keyed by date', () async {
    await repo.upsert(holiday, t0);
    await repo.upsert(busy, t0);

    expect(await repo.watchAll().first, {christmas: holiday, saturday: busy});
  });

  test('upsert replaces the override for the same date', () async {
    await repo.upsert(holiday, t0);
    final changed = DayOverride(date: christmas, capacity: 1);
    await repo.upsert(changed, t1);

    expect(await repo.watchAll().first, {christmas: changed});
    final row = await db.select(db.dayOverrides).getSingle();
    expect(row.note, isNull);
    expect(row.updatedAt, t1);
  });

  test('remove is a soft delete', () async {
    await repo.upsert(holiday, t0);
    await repo.upsert(busy, t0);
    await repo.remove(christmas, t1);

    expect(await repo.watchAll().first, {saturday: busy});
    final rows = await db.select(db.dayOverrides).get();
    final removed = rows.singleWhere((row) => row.date == christmas);
    expect(removed.deletedAt, t1);
    expect(removed.updatedAt, t1);
  });

  test('removing twice keeps the first deletion time', () async {
    await repo.upsert(holiday, t0);
    await repo.remove(christmas, t1);
    await repo.remove(christmas, t2);

    final row = await db.select(db.dayOverrides).getSingle();
    expect(row.deletedAt, t1);
    expect(row.updatedAt, t1);
  });

  test('removing a date without an override does nothing', () async {
    await repo.remove(christmas, t1);

    expect(await db.select(db.dayOverrides).get(), isEmpty);
  });

  test('upsert after remove brings the override back', () async {
    await repo.upsert(holiday, t0);
    await repo.remove(christmas, t1);
    await repo.upsert(holiday, t2);

    expect(await repo.watchAll().first, {christmas: holiday});
    final row = await db.select(db.dayOverrides).getSingle();
    expect(row.deletedAt, isNull);
    expect(row.updatedAt, t2);
  });

  test('the stream emits on each write', () async {
    final seen = <Set<LocalDate>>[];
    final subscription = repo.watchAll().listen(
      (overrides) => seen.add(overrides.keys.toSet()),
    );
    await pumpEventQueue();
    await repo.upsert(holiday, t0);
    await pumpEventQueue();
    await repo.upsert(busy, t0);
    await pumpEventQueue();
    await repo.remove(christmas, t1);
    await pumpEventQueue();
    await subscription.cancel();

    expect(seen, [
      <LocalDate>{},
      {christmas},
      {christmas, saturday},
      {saturday},
    ]);
  });
}
