import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_task_repository.dart';
import 'package:tasks_order/data/repository/task_mapper.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/series.dart';
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
        weight: 4,
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

    test('the stored successor carries the weight (D21)', () async {
      final a = task('a')
          .copyWith(dueDate: today, weight: 4)
          .setRecurrence(monthly, today: today, now: t0);
      await repo.upsert(a, t0);

      await repo.complete('a', t1, onPlan: true, today: today);

      expect((await stored(a.successorId)).weight, 4);
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
      // A second active instance of the same series, as in data broken
      // before T-713 (upsert no longer lets it happen): written directly.
      await db
          .into(db.tasks)
          .insert(
            task('b')
                .copyWith(
                  recurrence: monthly,
                  seriesId: 'a',
                  occurrenceDate: today,
                )
                .toRow(),
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

    test('undo with a touched successor is refused until asked as an '
        'ordinary task; then the task loses its rule (T-713)', () async {
      final a = await storeRecurring('a');
      await repo.complete('a', t1, onPlan: true, today: today);
      await repo.setFocus(a.successorId, true, t2);

      expect(await repo.uncomplete('a', t2), UncompleteCheck.successorChanged);
      expect((await stored('a')).isDone, isTrue);

      expect(
        await repo.uncomplete('a', t2, asOrdinary: true),
        UncompleteCheck.allowed,
      );

      final next = await stored(a.successorId);
      expect(next.recurrence, monthly);
      final back = await stored('a');
      expect(back.isDone, isFalse);
      expect(back.recurrence, isNull);
      expect(back.seriesId, 'a');
    });

    test('an older completion cannot be taken back (T-713)', () async {
      final a = await storeRecurring('a');
      await repo.complete('a', t1, onPlan: true, today: today);
      await repo.complete(a.successorId, t2, onPlan: true, today: today);
      final second = await stored(a.successorId);

      expect(await repo.uncomplete('a', t2), UncompleteCheck.notLast);
      expect((await stored('a')).isDone, isTrue);
      expect(
        await repo.uncomplete('a', t2, asOrdinary: true),
        UncompleteCheck.notLast,
      );

      // The last one still can, and takes its own successor away.
      expect(await repo.uncomplete(second.id, t2), UncompleteCheck.allowed);
      expect(await repo.getById(second.successorId), isNull);
      expect((await stored(second.id)).recurrence, monthly);
      // The second is active again (and changed): the first is now the
      // last completion, but may come back only as an ordinary task.
      expect(await repo.uncomplete('a', t2), UncompleteCheck.successorChanged);
    });

    test('an ordinary task of a series comes back as before', () async {
      await repo.upsert(task('o').copyWith(seriesId: 'a'), t0);
      await storeRecurring('a');
      await repo.complete('o', t1, onPlan: false);

      expect(await repo.uncomplete('o', t2), UncompleteCheck.allowed);
      expect((await stored('o')).isDone, isFalse);
    });

    group('one active instance with a rule per series (T-713)', () {
      test(
        'a rule set on a copy of a going series starts its own series',
        () async {
          final a = await storeRecurring('a');
          await repo.complete('a', t1, onPlan: true, today: today);
          await repo.setFocus(a.successorId, true, t2);
          await repo.uncomplete('a', t2, asOrdinary: true);
          final copy = await stored('a');
          expect(copy.recurrence, isNull);
          expect(copy.seriesId, 'a');

          // The editor sets a rule on the copy.
          await repo.upsert(
            copy.setRecurrence(monthly, today: today, now: t2),
            t2,
          );

          // It becomes a new task of a new series: with the old id its
          // successor would take the id of the old successor and overwrite
          // it (found on the emulator).
          expect(await repo.getById('a'), isNull);
          final edited = (await repo.watchActive().first).singleWhere(
            (t) => t.id != a.successorId,
          );
          expect(edited.title, 'Task a');
          expect(edited.recurrence, isNotNull);
          expect(edited.seriesId, edited.id);
          final next = await stored(a.successorId);
          expect(next.seriesId, 'a');
          expect(next.recurrence, monthly);

          // Completing it leaves the old series alone.
          await repo.complete(edited.id, t2, onPlan: false, today: today);
          final kept = await stored(a.successorId);
          expect(kept.isFocused, isTrue);
          expect(kept.seriesId, 'a');
          expect((await stored(edited.successorId)).seriesId, edited.id);
        },
      );

      test('editing the active instance keeps its series', () async {
        final a = await storeRecurring('a');

        await repo.upsert(a.copyWith(title: 'Rent'), t1);

        expect((await stored('a')).seriesId, 'a');
      });
    });

    test('skip: the instance to the Trash, the successor comes', () async {
      final a = await storeRecurring('a');

      await repo.skip('a', t1, today: today);

      expect((await stored('a')).isDeleted, isTrue);
      expect((await stored(a.successorId)).isDeleted, isFalse);
    });

    group('from completion ahead of its day (T-712)', () {
      final every10 = Recurrence.interval(
        every: 10,
        unit: RecurrenceUnit.day,
        afterDone: true,
      );
      final ahead = today.addDays(10);

      /// A haircut available from ten days on, as a successor stores it.
      Future<Task> storeHaircut() async {
        final t = task('h')
            .copyWith(notBefore: ahead)
            .setRecurrence(every10, today: today, now: t0);
        await repo.upsert(t, t0);
        return stored('h');
      }

      test('a skip counts from the instance\'s date', () async {
        final h = await storeHaircut();

        await repo.skip('h', t1, today: today);

        final next = await stored(h.successorId);
        expect(next.notBefore, ahead.addDays(10));
        expect(next.occurrenceDate, ahead.addDays(10));
      });

      test('a completion counts from today', () async {
        final h = await storeHaircut();

        await repo.complete('h', t1, onPlan: false, today: today);

        expect((await stored(h.successorId)).notBefore, today.addDays(10));
      });
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
