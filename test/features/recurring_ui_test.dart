import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/shared/task_card.dart';

import 'app_harness.dart';

/// T-708: recurring tasks and their ghosts in the lists. The harness day is
/// Friday 13 November 2026; capacity Mon..Fri 1, Sat 3, Sun 0.
void main() {
  final today = AppHarness.today;
  final weekly = Recurrence.interval(
    every: 1,
    unit: RecurrenceUnit.week,
    anchor: today,
  );

  /// Weekly from today, without dates.
  Task recurring(String id) =>
      testTask(id).setRecurrence(weekly, today: today, now: AppHarness.now);

  Future<AppHarness> start(WidgetTester tester, List<Task> tasks) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return AppHarness.start(tester, tasks: tasks);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<List<Task>> all(AppHarness app) => app.real(
    () => app.container.read(taskRepositoryProvider).watchAll().first,
  );

  group('Plan', () {
    testWidgets('ghosts are dimmed, without a checkbox, and open the task', (
      tester,
    ) async {
      await start(tester, [recurring('w')]);
      await tap(tester, find.byIcon(Icons.calendar_month_outlined));

      final ghost = find.byKey(const ValueKey('w@2026-11-20'));
      expect(ghost, findsOneWidget);
      expect(tester.widget(ghost), isA<GhostTaskCard>());
      expect(
        find.descendant(of: ghost, matching: find.byType(TaskDoneButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: ghost, matching: find.byIcon(Icons.repeat)),
        findsOneWidget,
      );
      // The stored task itself is today, with its checkbox.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('w')),
          matching: find.byType(TaskDoneButton),
        ),
        findsOneWidget,
      );
      // Its day counts it: Friday Nov 20, capacity 1.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('day-2026-11-20')),
          matching: find.text('1/1'),
        ),
        findsOneWidget,
      );

      await tap(tester, ghost);
      expect(find.text('Edit task'), findsOneWidget);
    });
  });

  group('lists', () {
    testWidgets('a recurring task shows the repeat icon', (tester) async {
      await start(tester, [recurring('w'), testTask('p', minute: 1)]);
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      expect(
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task w'),
          matching: find.byIcon(Icons.repeat),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task p'),
          matching: find.byIcon(Icons.repeat),
        ),
        findsNothing,
      );
    });

    testWidgets('the Tasks list shows the day of the task, not of a ghost', (
      tester,
    ) async {
      await start(tester, [recurring('w')]);
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      expect(
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task w'),
          matching: find.text('Today'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Recurring filter shows only recurring tasks', (
      tester,
    ) async {
      await start(tester, [recurring('w'), testTask('p', minute: 1)]);
      await tap(tester, find.byIcon(Icons.checklist_outlined));
      final chip = find.byKey(const ValueKey('filter-recurring'));
      await tester.ensureVisible(chip);
      await tap(tester, chip);

      expect(find.widgetWithText(TaskCard, 'Task w'), findsOneWidget);
      expect(find.widgetWithText(TaskCard, 'Task p'), findsNothing);
    });

    testWidgets('a task that is not released yet says from when', (
      tester,
    ) async {
      await start(tester, [
        testTask('n').copyWith(notBefore: LocalDate(2026, 11, 20)),
        testTask('r', minute: 1).copyWith(notBefore: today),
      ]);
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      expect(
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task n'),
          matching: find.textContaining('From '),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task r'),
          matching: find.textContaining('From '),
        ),
        findsNothing,
      );
    });
  });

  group('delete warns that the series stops (T-711)', () {
    Future<AppHarness> openEditor(WidgetTester tester) async {
      final app = await start(tester, [recurring('w')]);
      await tap(tester, find.byIcon(Icons.checklist_outlined));
      await openEditorOf(tester, find.text('Task w'));
      await tap(tester, find.byIcon(Icons.delete_outline));
      expect(find.text('Delete the series?'), findsOneWidget);
      expect(find.text('Skip this time'), findsNothing);
      return app;
    }

    testWidgets('delete the series: nothing comes after it', (tester) async {
      final app = await openEditor(tester);

      await tap(tester, find.byKey(const ValueKey('deleteSeries')));

      expect((await app.task('w')).isDeleted, isTrue);
      expect(await all(app), isEmpty);
      expect(find.text('Moved to Trash'), findsOneWidget);
    });

    testWidgets('cancel keeps the task and the editor', (tester) async {
      final app = await openEditor(tester);

      await tap(tester, find.text('Cancel'));

      expect((await app.task('w')).isDeleted, isFalse);
      expect(find.text('Edit task'), findsOneWidget);
    });
  });

  group('skip this time from the long-press menu (T-711)', () {
    testWidgets('Today: the next repeat comes', (tester) async {
      final app = await start(tester, [recurring('w')]);

      await openMenuOf(tester, find.text('Task w'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('menuSkip')));

      expect((await app.task('w')).isDeleted, isTrue);
      final next = await app.task(recurring('w').successorId);
      expect(next.isDeleted, isFalse);
      expect(next.notBefore, LocalDate(2026, 11, 20));
      expect(find.textContaining('Skipped'), findsOneWidget);
    });

    testWidgets('Plan: undo takes the next repeat away again', (tester) async {
      final app = await start(tester, [recurring('w')]);
      await tap(tester, find.byIcon(Icons.calendar_month_outlined));

      await openMenuOf(tester, find.byKey(const ValueKey('w')));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('menuSkip')));
      await tap(tester, find.text('Undo'));

      expect((await app.task('w')).isDeleted, isFalse);
      expect((await all(app)).map((t) => t.id), ['w']);
    });

    testWidgets('an ordinary task has no skip', (tester) async {
      await start(tester, [testTask('p')]);

      await openMenuOf(tester, find.text('Task p'));
      await tester.pumpAndSettle();

      expect(find.text('Pin to a day…'), findsOneWidget);
      expect(find.byKey(const ValueKey('menuSkip')), findsNothing);
    });
  });

  group('from completion: one completion a day (T-710)', () {
    final every10 = Recurrence.interval(
      every: 10,
      unit: RecurrenceUnit.day,
      afterDone: true,
    );
    Task haircut() =>
        testTask('h').setRecurrence(every10, today: today, now: AppHarness.now);

    testWidgets('the next one is paused, a tick explains and does nothing', (
      tester,
    ) async {
      final app = await start(tester, [haircut()]);
      final nextId = haircut().successorId;
      await tap(tester, find.byType(TaskDoneButton).first);
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      final tile = find.widgetWithText(TaskCard, 'Task h');
      expect(
        find.descendant(of: tile, matching: find.text('Paused until tomorrow')),
        findsOneWidget,
      );

      await tap(
        tester,
        find.descendant(of: tile, matching: find.byType(TaskDoneButton)),
      );

      expect(
        find.text(
          'Already done today. The next one can be ticked from tomorrow.',
        ),
        findsOneWidget,
      );
      expect((await app.task(nextId)).isDone, isFalse);
      expect(await all(app), hasLength(2));
    });

    testWidgets('undo of the completion lifts the pause', (tester) async {
      await start(tester, [haircut()]);
      await tap(tester, find.byType(TaskDoneButton).first);
      await tap(tester, find.text('Completed'));
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      expect(find.text('Paused until tomorrow'), findsNothing);
    });

    testWidgets('a series by the calendar is not paused', (tester) async {
      final app = await start(tester, [recurring('w')]);
      final nextId = recurring('w').successorId;
      await tap(tester, find.byType(TaskDoneButton).first);
      await tap(tester, find.byIcon(Icons.checklist_outlined));

      expect(find.text('Paused until tomorrow'), findsNothing);
      await tap(
        tester,
        find.descendant(
          of: find.widgetWithText(TaskCard, 'Task w'),
          matching: find.byType(TaskDoneButton),
        ),
      );
      expect((await app.task(nextId)).isDone, isTrue);
    });
  });

  group('only the last completion comes back (T-713)', () {
    DateTime at(int minutes) =>
        AppHarness.now.subtract(Duration(minutes: 60 - minutes));

    Future<void> openDone(WidgetTester tester) async {
      await tap(tester, find.byIcon(Icons.checklist_outlined));
      final chip = find.byKey(const ValueKey('filter-done'));
      await tester.ensureVisible(chip);
      await tap(tester, chip);
    }

    Finder completedOf(String id) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byType(TaskDoneButton),
    );

    testWidgets('an older completion is dimmed and only explains', (
      tester,
    ) async {
      final a = recurring('w');
      final s1 = a.successor(now: at(1), today: today);
      final s2 = s1.successor(now: at(2), today: today);
      final app = await start(tester, [
        a.complete(at(1), onPlan: false),
        s1.complete(at(2), onPlan: false),
        s2,
      ]);
      await openDone(tester);

      Opacity opacityOf(String id) => tester.widget<Opacity>(
        find
            .ancestor(of: completedOf(id), matching: find.byType(Opacity))
            .first,
      );
      expect(opacityOf('w').opacity, lessThan(1));
      expect(opacityOf(s1.id).opacity, 1);

      await tester.ensureVisible(completedOf('w'));
      await tap(tester, completedOf('w'));

      expect(
        find.text('Only the last completion of this series can be taken back.'),
        findsOneWidget,
      );
      expect((await app.task('w')).isDone, isTrue);
      expect(await all(app), hasLength(3));
    });

    testWidgets('a changed next repeat asks; Cancel keeps it done, the '
        'answer brings it back without the rule', (tester) async {
      final a = recurring('w');
      final next = a.successor(now: at(1), today: today);
      final app = await start(tester, [a.complete(at(1), onPlan: false), next]);
      // The next repeat is changed after it came.
      await app.real(
        () => app.container
            .read(taskRepositoryProvider)
            .setFocus(next.id, true, AppHarness.now),
      );
      await tester.pumpAndSettle();
      await openDone(tester);

      await tester.ensureVisible(completedOf('w'));
      await tap(tester, completedOf('w'));
      expect(find.text('The series has changed'), findsOneWidget);
      expect(
        find.textContaining('Bring this task back as an ordinary one'),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancel'));
      expect((await app.task('w')).isDone, isTrue);

      await tap(tester, completedOf('w'));
      await tap(tester, find.byKey(const ValueKey('bringBackAsOrdinary')));

      final back = await app.task('w');
      expect(back.isDone, isFalse);
      expect(back.recurrence, isNull);
      expect((await app.task(next.id)).recurrence, weekly);
    });

    testWidgets('the last completion with an untouched next one comes back '
        'with its rule, without a question', (tester) async {
      final a = recurring('w');
      final app = await start(tester, [
        a.complete(at(1), onPlan: false),
        a.successor(now: at(1), today: today),
      ]);
      await openDone(tester);

      await tester.ensureVisible(completedOf('w'));
      await tap(tester, completedOf('w'));

      expect(find.text('The series has changed'), findsNothing);
      final back = await app.task('w');
      expect(back.isDone, isFalse);
      expect(back.recurrence, weekly);
      expect(await all(app), hasLength(1));
    });
  });

  testWidgets('complete: the successor comes with its date; undo takes it '
      'away', (tester) async {
    final app = await start(tester, [recurring('w')]);
    final successorId = recurring('w').successorId;

    await tap(tester, find.byType(TaskDoneButton).first);

    final next = await app.task(successorId);
    expect(next.isDone, isFalse);
    expect(next.notBefore, LocalDate(2026, 11, 20));
    expect(next.occurrenceDate, LocalDate(2026, 11, 20));

    await tap(tester, find.text('Completed'));

    expect((await all(app)).map((t) => t.id), ['w']);
    expect((await app.task('w')).isDone, isFalse);
  });
}
