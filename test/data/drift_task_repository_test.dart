import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_task_repository.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';

import 'test_database.dart';

void main() {
  late AppDatabase db;
  late DriftTaskRepository repo;

  // Whole milliseconds: the database keeps nothing finer.
  final t0 = DateTime.utc(2026, 11, 13, 8);
  final t1 = t0.add(const Duration(minutes: 1));
  final t2 = t0.add(const Duration(minutes: 2));

  setUp(() {
    db = newTestDatabase();
    repo = DriftTaskRepository(db);
  });
  tearDown(() => db.close());

  Task task(String id, {DateTime? createdAt, int priority = 2}) => Task.create(
    id: id,
    title: 'Task $id',
    priority: priority,
    now: createdAt ?? t0,
  );

  Future<Task> stored(String id) async => (await repo.getById(id))!;

  List<String> ids(List<Task> tasks) => [for (final t in tasks) t.id];

  group('upsert / getById', () {
    test('a stored task is read back with every field', () async {
      final full = Task(
        id: 'a',
        title: 'File the report',
        notes: 'with the appendix',
        priority: 1,
        dueDate: LocalDate(2026, 11, 20),
        isFocused: true,
        focusedAt: t0,
        pinnedDate: LocalDate(2026, 11, 18),
        notBefore: LocalDate(2026, 11, 14),
        status: TaskStatus.done,
        createdAt: t0,
        updatedAt: t0,
        completedAt: t0,
        completedOnPlan: true,
        deletedAt: t0,
      );
      await repo.upsert(full, t0);

      expect(await repo.getById('a'), full);
    });

    test('getById is null for an unknown id', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('upsert replaces the task with the same id', () async {
      await repo.upsert(task('a'), t0);
      final edited = (await stored('a'))
          .copyWith(title: 'Renamed', dueDate: LocalDate(2026, 12, 1));
      await repo.upsert(edited, t1);

      final read = await stored('a');
      expect(read.title, 'Renamed');
      expect(read.dueDate, LocalDate(2026, 12, 1));
      expect(await repo.watchAll().first, hasLength(1));
    });

    test('upsert clears the fields that became null', () async {
      final full = task('a').copyWith(
        notes: 'call first',
        dueDate: LocalDate(2026, 11, 20),
        pinnedDate: LocalDate(2026, 11, 18),
      );
      await repo.upsert(full, t0);
      await repo.upsert(
        full.copyWith(notes: null, dueDate: null, pinnedDate: null),
        t1,
      );

      final read = await stored('a');
      expect(read.notes, isNull);
      expect(read.dueDate, isNull);
      expect(read.pinnedDate, isNull);
    });

    test('upsert stamps updatedAt and keeps createdAt', () async {
      await repo.upsert(task('a'), t1);

      final read = await stored('a');
      expect(read.createdAt, t0);
      expect(read.updatedAt, t1);
    });
  });

  group('transitions', () {
    setUp(() => repo.upsert(task('a'), t0));

    test('complete marks the task done on or off the plan', () async {
      await repo.upsert(task('b'), t0);
      await repo.complete('a', t1, onPlan: true);
      await repo.complete('b', t1, onPlan: false);

      final a = await stored('a');
      expect(a.status, TaskStatus.done);
      expect(a.completedAt, t1);
      expect(a.completedOnPlan, isTrue);
      expect(a.updatedAt, t1);
      expect((await stored('b')).completedOnPlan, isFalse);
    });

    test(
      'complete stores the plan day, uncomplete clears it (T-907)',
      () async {
        final thursday = LocalDate(2026, 11, 19);
        await repo.complete('a', t1, onPlan: false, plannedDate: thursday);
        expect((await stored('a')).completedPlanDate, thursday);

        await repo.uncomplete('a', t2);
        expect((await stored('a')).completedPlanDate, isNull);
      },
    );

    test('uncomplete returns the task to active', () async {
      await repo.complete('a', t1, onPlan: true);
      await repo.uncomplete('a', t2);

      final a = await stored('a');
      expect(a.status, TaskStatus.active);
      expect(a.completedAt, isNull);
      expect(a.completedOnPlan, isFalse);
      expect(a.updatedAt, t2);
    });

    test('setFocus sets and clears the mark', () async {
      await repo.setFocus('a', true, t1);
      var a = await stored('a');
      expect(a.isFocused, isTrue);
      expect(a.focusedAt, t1);
      expect(a.updatedAt, t1);

      await repo.setFocus('a', false, t2);
      a = await stored('a');
      expect(a.isFocused, isFalse);
      expect(a.focusedAt, isNull);
      expect(a.updatedAt, t2);
    });

    test(
      'delete moves the task to the Trash, restore brings it back',
      () async {
        await repo.delete('a', t1);
        var a = await stored('a');
        expect(a.deletedAt, t1);
        expect(a.updatedAt, t1);

        await repo.restore('a', t2);
        a = await stored('a');
        expect(a.isDeleted, isFalse);
        expect(a.updatedAt, t2);
      },
    );

    test(
      'a transition that changes nothing does not touch updatedAt',
      () async {
        await repo.uncomplete('a', t1);
        await repo.setFocus('a', false, t1);
        await repo.restore('a', t1);

        expect((await stored('a')).updatedAt, t0);
      },
    );

    test('an unknown id is ignored', () async {
      await repo.complete('nope', t1, onPlan: true);
      await repo.uncomplete('nope', t1);
      await repo.setFocus('nope', true, t1);
      await repo.delete('nope', t1);
      await repo.restore('nope', t1);

      expect(ids(await repo.watchAll().first), ['a']);
    });
  });

  group('queries', () {
    setUp(() async {
      // Inserted out of order on purpose.
      await repo.upsert(task('done', createdAt: t1), t1);
      await repo.upsert(task('active-new', createdAt: t2), t2);
      await repo.upsert(task('active-old'), t0);
      await repo.upsert(task('trashed'), t0);
      await repo.upsert(task('trashed-done'), t0);
      await repo.complete('done', t2, onPlan: true);
      await repo.complete('trashed-done', t2, onPlan: false);
      await repo.delete('trashed-done', t1);
      await repo.delete('trashed', t2);
    });

    test('watchActive: to do, not deleted, oldest first', () async {
      expect(ids(await repo.watchActive().first), ['active-old', 'active-new']);
    });

    test('watchAll: active and done, not deleted, oldest first', () async {
      expect(ids(await repo.watchAll().first), [
        'active-old',
        'done',
        'active-new',
      ]);
    });

    test('watchTrash: deleted only, the latest deletion first', () async {
      expect(ids(await repo.watchTrash().first), ['trashed', 'trashed-done']);
    });

    test('tasks created at the same instant are ordered by id', () async {
      await repo.upsert(task('b', createdAt: t0), t0);
      await repo.upsert(task('a', createdAt: t0), t0);

      expect(ids(await repo.watchActive().first).take(3), [
        'a',
        'active-old',
        'b',
      ]);
    });
  });

  group('deleteForever', () {
    test('removes the task, active or in the Trash', () async {
      await repo.upsert(task('a'), t0);
      await repo.upsert(task('b'), t0);
      await repo.upsert(task('kept'), t0);
      await repo.delete('b', t1);

      await repo.deleteForever('a');
      await repo.deleteForever('b');
      await repo.deleteForever('nope');

      expect(await repo.getById('a'), isNull);
      expect(await repo.getById('b'), isNull);
      expect(ids(await repo.watchAll().first), ['kept']);
      expect(await repo.watchTrash().first, isEmpty);
    });
  });

  group('purgeDeleted', () {
    const month = Duration(days: 30);

    test('removes only what has been in the Trash long enough', () async {
      final now = t0.add(const Duration(days: 40));
      await repo.upsert(task('old'), t0);
      await repo.upsert(task('recent'), t0);
      await repo.upsert(task('kept'), t0);
      await repo.delete('old', now.subtract(const Duration(days: 31)));
      await repo.delete('recent', now.subtract(const Duration(days: 29)));

      expect(await repo.purgeDeleted(month, now), 1);

      expect(await repo.getById('old'), isNull);
      expect(ids(await repo.watchTrash().first), ['recent']);
      expect(ids(await repo.watchActive().first), ['kept']);
    });

    test('a task deleted exactly at the limit stays', () async {
      final now = t0.add(month);
      await repo.upsert(task('edge'), t0);
      await repo.delete('edge', t0);

      expect(await repo.purgeDeleted(month, now), 0);
    });
  });

  group('streams emit on each write', () {
    /// Collects what [stream] emits; drift answers asynchronously, so let the
    /// event queue run after each write.
    Future<List<List<String>>> record(
      Stream<List<Task>> stream,
      List<Future<void> Function()> writes,
    ) async {
      final seen = <List<String>>[];
      final subscription = stream.listen((tasks) => seen.add(ids(tasks)));
      await pumpEventQueue();
      for (final write in writes) {
        await write();
        await pumpEventQueue();
      }
      await subscription.cancel();
      return seen;
    }

    test('watchActive', () async {
      final seen = await record(repo.watchActive(), [
        () => repo.upsert(task('a'), t0),
        () => repo.upsert(task('b', createdAt: t1), t1),
        () => repo.setFocus('a', true, t1),
        () => repo.complete('a', t1, onPlan: true),
        () => repo.uncomplete('a', t2),
        () => repo.delete('b', t2),
        () => repo.restore('b', t2),
      ]);

      expect(seen, [
        <String>[],
        ['a'],
        ['a', 'b'],
        ['a', 'b'],
        ['b'],
        ['a', 'b'],
        ['a'],
        ['a', 'b'],
      ]);
    });

    test('watchAll and watchTrash', () async {
      await repo.upsert(task('a'), t0);

      final all = await record(repo.watchAll(), [
        () => repo.complete('a', t1, onPlan: false),
        () => repo.delete('a', t2),
      ]);
      expect(all, [
        ['a'],
        ['a'],
        <String>[],
      ]);

      final trash = await record(repo.watchTrash(), [
        () => repo.restore('a', t2),
        () => repo.delete('a', t2),
        () => repo
            .purgeDeleted(Duration.zero, t2.add(const Duration(days: 1)))
            .then((_) {}),
      ]);
      expect(trash, [
        ['a'],
        <String>[],
        ['a'],
        <String>[],
      ]);
    });
  });

  group('recurring tasks (D20, T-705)', () {
    final today = LocalDate(2026, 11, 13);
    final monthly = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.month,
      anchor: today,
    );

    /// A monthly task due today, stored.
    Future<Task> storeRecurring(String id) async {
      final t = task(id)
          .copyWith(dueDate: today)
          .setRecurrence(monthly, today: today, now: t0);
      await repo.upsert(t, t0);
      return stored(id);
    }

    test('a recurring task is stored with its rule', () async {
      final t = await storeRecurring('a');

      expect(t.recurrence, monthly);
      expect(t.seriesId, 'a');
      expect(t.occurrenceDate, today);
    });

    test('complete inserts the successor in the same transaction', () async {
      final a = await storeRecurring('a');
      final seen = <List<Task>>[];
      final sub = repo.watchAll().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      seen.clear();

      await repo.complete('a', t1, onPlan: true, today: today);
      await pumpEventQueue();

      // One emission: the plan is recomputed once (ADR-13).
      expect(seen, hasLength(1));
      final next = await stored(a.successorId);
      expect(next.isDone, isFalse);
      expect(next.seriesId, 'a');
      expect(next.dueDate, LocalDate(2026, 12, 13));
      expect(next.createdAt, t1);
      expect((await stored('a')).isDone, isTrue);
    });

    test('a second complete changes nothing', () async {
      await storeRecurring('a');
      await repo.complete('a', t1, onPlan: true, today: today);
      await repo.complete('a', t2, onPlan: true, today: today);

      final all = await repo.watchAll().first;
      expect(all, hasLength(2));
    });

    test('no successor while the series has another active instance', () async {
      final a = await storeRecurring('a');
      // A second active instance of the same series, e.g. a restored skip.
      await repo.upsert(
        task(
          'b',
        ).copyWith(recurrence: monthly, seriesId: 'a', occurrenceDate: today),
        t0,
      );

      await repo.complete('a', t1, onPlan: true, today: today);

      expect(await repo.getById(a.successorId), isNull);
    });

    test('undo removes an untouched successor', () async {
      final a = await storeRecurring('a');
      await repo.complete('a', t1, onPlan: true, today: today);

      await repo.uncomplete('a', t2);

      expect(await repo.getById(a.successorId), isNull);
      final back = await stored('a');
      expect(back.isDone, isFalse);
      expect(back.recurrence, monthly);
    });

    test('undo keeps a touched successor and the returning task loses its '
        'rule', () async {
      final a = await storeRecurring('a');
      await repo.complete('a', t1, onPlan: true, today: today);
      await repo.setFocus(a.successorId, true, t2);

      await repo.uncomplete('a', t2);

      final next = await stored(a.successorId);
      expect(next.recurrence, monthly);
      final back = await stored('a');
      expect(back.isDone, isFalse);
      expect(back.recurrence, isNull);
      expect(back.seriesId, 'a');
    });

    test('skip: the instance to the Trash, the successor comes', () async {
      final a = await storeRecurring('a');

      await repo.skip('a', t1, today: today);

      expect((await stored('a')).isDeleted, isTrue);
      expect((await stored(a.successorId)).isDeleted, isFalse);
    });

    test('delete the series: to the Trash with its rule, no successor; '
        'restore resumes it', () async {
      final a = await storeRecurring('a');

      await repo.delete('a', t1);
      expect(await repo.getById(a.successorId), isNull);
      expect((await stored('a')).recurrence, monthly);

      await repo.restore('a', t2);
      final back = await stored('a');
      expect(back.isDeleted, isFalse);
      expect(back.recurrence, monthly);
    });

    test('restoring a skipped instance removes the untouched successor '
        '(undo of a skip)', () async {
      final a = await storeRecurring('a');
      await repo.skip('a', t1, today: today);

      await repo.restore('a', t2);

      expect(await repo.getById(a.successorId), isNull);
      final back = await stored('a');
      expect(back.isDeleted, isFalse);
      expect(back.recurrence, monthly);
    });

    test('restoring a skipped instance while the series goes on returns it '
        'without the rule', () async {
      final a = await storeRecurring('a');
      await repo.skip('a', t1, today: today);
      // The successor has been used since.
      await repo.setFocus(a.successorId, true, t2);

      await repo.restore('a', t2);

      final back = await stored('a');
      expect(back.isDeleted, isFalse);
      expect(back.recurrence, isNull);
      expect(back.seriesId, 'a');
    });

    test('an ordinary task completes as before', () async {
      await repo.upsert(task('p'), t0);

      await repo.complete('p', t1, onPlan: false);

      expect(await repo.watchAll().first, hasLength(1));
    });
  });
}
