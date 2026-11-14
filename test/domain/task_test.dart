import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 13, 9);
  final t1 = DateTime.utc(2026, 11, 13, 18, 30);
  final t2 = DateTime.utc(2026, 11, 14, 8);

  Task newTask({bool isFocused = false}) => Task.create(
    title: 'Pay rent',
    priority: 2,
    now: t0,
    isFocused: isFocused,
    id: 'id-1',
  );

  final isAssertionError = throwsA(isA<AssertionError>());

  group('Task.create', () {
    test('builds an active task with defaults', () {
      final task = Task.create(title: 'Pay rent', priority: 2, now: t0);

      expect(task.title, 'Pay rent');
      expect(task.priority, 2);
      expect(task.status, TaskStatus.active);
      expect(task.isDone, isFalse);
      expect(task.isDeleted, isFalse);
      expect(task.isFocused, isFalse);
      expect(task.focusedAt, isNull);
      expect(task.completedOnPlan, isFalse);
      expect(task.notes, isNull);
      expect(task.dueDate, isNull);
      expect(task.pinnedDate, isNull);
      expect(task.notBefore, isNull);
      expect(task.completedAt, isNull);
      expect(task.deletedAt, isNull);
      expect(task.createdAt, t0);
      expect(task.updatedAt, t0);
    });

    test('keeps the optional fields', () {
      final task = Task.create(
        title: 'Pay rent',
        priority: 1,
        now: t0,
        dueDate: LocalDate(2026, 11, 20),
        notes: 'via bank app',
      );
      expect(task.dueDate, LocalDate(2026, 11, 20));
      expect(task.notes, 'via bank app');
    });

    test('generates a distinct UUID v4 per task', () {
      final a = Task.create(title: 'a', priority: 1, now: t0);
      final b = Task.create(title: 'b', priority: 1, now: t0);
      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(a.id, matches(uuidV4));
      expect(b.id, matches(uuidV4));
      expect(a.id, isNot(b.id));
    });

    test('uses the given id', () {
      expect(newTask().id, 'id-1');
    });

    test('trims the title', () {
      final task = Task.create(title: '  Pay rent \n', priority: 2, now: t0);
      expect(task.title, 'Pay rent');
    });

    test('rejects a blank title', () {
      expect(
        () => Task.create(title: '', priority: 1, now: t0),
        throwsArgumentError,
      );
      expect(
        () => Task.create(title: '  \t', priority: 1, now: t0),
        throwsArgumentError,
      );
    });

    test('rejects a priority outside 1..10', () {
      expect(
        () => Task.create(title: 'x', priority: 0, now: t0),
        throwsArgumentError,
      );
      expect(
        () => Task.create(title: 'x', priority: 11, now: t0),
        throwsArgumentError,
      );
    });

    test('created focused records when it was focused', () {
      final task = newTask(isFocused: true);
      expect(task.isFocused, isTrue);
      expect(task.focusedAt, t0);
    });

    test('stores instants in UTC', () {
      final local = DateTime(2026, 11, 13, 9);
      final task = Task.create(
        title: 'x',
        priority: 1,
        now: local,
        isFocused: true,
      );
      expect(task.createdAt.isUtc, isTrue);
      expect(task.updatedAt.isUtc, isTrue);
      expect(task.focusedAt!.isUtc, isTrue);
      expect(task.createdAt, local.toUtc());
    });
  });

  group('invariants', () {
    test('title must not be blank', () {
      expect(() => newTask().copyWith(title: ' '), isAssertionError);
    });

    test('priority is a level 1..10', () {
      expect(() => newTask().copyWith(priority: 0), isAssertionError);
      expect(() => newTask().copyWith(priority: 11), isAssertionError);
      expect(newTask().copyWith(priority: 10).priority, 10);
    });

    test('completedAt is set exactly when the task is done', () {
      expect(
        () => newTask().copyWith(status: TaskStatus.done),
        isAssertionError,
      );
      expect(() => newTask().copyWith(completedAt: t1), isAssertionError);
    });

    test('focusedAt is set exactly when isFocused is true', () {
      expect(() => newTask().copyWith(isFocused: true), isAssertionError);
      expect(() => newTask().copyWith(focusedAt: t1), isAssertionError);
    });

    test('completedOnPlan needs a done task', () {
      expect(() => newTask().copyWith(completedOnPlan: true), isAssertionError);
    });
  });

  group('complete / uncomplete', () {
    test('complete marks the task done and bumps updatedAt', () {
      final done = newTask().complete(t1, onPlan: true);
      expect(done.status, TaskStatus.done);
      expect(done.isDone, isTrue);
      expect(done.completedAt, t1);
      expect(done.updatedAt, t1);
      expect(done.createdAt, t0);
    });

    test('complete records whether the task was on the list of today', () {
      expect(newTask().complete(t1, onPlan: true).completedOnPlan, isTrue);
      expect(newTask().complete(t1, onPlan: false).completedOnPlan, isFalse);
    });

    test('complete keeps the Focus mark', () {
      final done = newTask(isFocused: true).complete(t1, onPlan: false);
      expect(done.isFocused, isTrue);
      expect(done.focusedAt, t0);
    });

    test('completing a done task changes nothing', () {
      final done = newTask().complete(t1, onPlan: true);
      expect(done.complete(t2, onPlan: false), same(done));
    });

    test('uncomplete returns the task to active', () {
      final active = newTask().complete(t1, onPlan: true).uncomplete(t2);
      expect(active.status, TaskStatus.active);
      expect(active.completedAt, isNull);
      expect(active.completedOnPlan, isFalse);
      expect(active.updatedAt, t2);
    });

    test('uncompleting an active task changes nothing', () {
      final task = newTask();
      expect(task.uncomplete(t1), same(task));
    });

    test('converts the instant to UTC', () {
      final done = newTask().complete(DateTime(2026, 11, 13, 20), onPlan: true);
      expect(done.completedAt!.isUtc, isTrue);
      expect(done.updatedAt.isUtc, isTrue);
    });
  });

  group('setFocus', () {
    test('focuses the task and records the instant', () {
      final focused = newTask().setFocus(true, t1);
      expect(focused.isFocused, isTrue);
      expect(focused.focusedAt, t1);
      expect(focused.updatedAt, t1);
    });

    test('removes the mark and clears the instant', () {
      final task = newTask(isFocused: true).setFocus(false, t1);
      expect(task.isFocused, isFalse);
      expect(task.focusedAt, isNull);
      expect(task.updatedAt, t1);
    });

    test('focusing again keeps the place in the Focus view', () {
      final focused = newTask().setFocus(true, t1);
      expect(focused.setFocus(true, t2), same(focused));
    });
  });

  group('trash / restore', () {
    test('trash soft-deletes the task', () {
      final deleted = newTask().trash(t1);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.deletedAt, t1);
      expect(deleted.updatedAt, t1);
      expect(deleted.status, TaskStatus.active);
    });

    test('trashing twice keeps the first deletion time', () {
      final deleted = newTask().trash(t1);
      expect(deleted.trash(t2), same(deleted));
    });

    test('restore clears deletedAt', () {
      final restored = newTask().trash(t1).restore(t2);
      expect(restored.isDeleted, isFalse);
      expect(restored.deletedAt, isNull);
      expect(restored.updatedAt, t2);
    });

    test('restoring a task that is not deleted changes nothing', () {
      final task = newTask();
      expect(task.restore(t1), same(task));
    });
  });

  group('value semantics', () {
    test('tasks with the same fields are equal', () {
      expect(newTask(), newTask());
      expect(newTask().hashCode, newTask().hashCode);
    });

    test('copyWith changes one field and can clear a nullable one', () {
      final task = newTask().copyWith(dueDate: LocalDate(2026, 11, 20));
      expect(task, isNot(newTask()));
      expect(task.copyWith(dueDate: null), newTask());
    });
  });
}
