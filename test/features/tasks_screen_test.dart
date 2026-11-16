import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/shared/task_card.dart';

import 'app_harness.dart';

void main() {
  /// Starts the app and opens the Tasks tab.
  Future<AppHarness> start(
    WidgetTester tester, {
    List<Task> tasks = const [],
    Settings? settings,
    Map<String, Object> stored = const {},
  }) async {
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      settings: settings,
      stored: stored,
    );
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    return app;
  }

  /// The titles of the active task cards, top to bottom.
  List<String> tiles(WidgetTester tester) => [
    for (final card in tester.widgetList<TaskCard>(find.byType(TaskCard)))
      if (!card.isDone) card.task.title,
  ];

  /// The titles of the done cards kept in the list (D22), top to bottom.
  List<String> doneTiles(WidgetTester tester) => [
    for (final card in tester.widgetList<TaskCard>(find.byType(TaskCard)))
      if (card.isDone) card.task.title,
  ];

  /// The label and the count of a filter chip, for example ['Focus', '2'].
  List<String> chip(WidgetTester tester, String name) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey('filter-$name')),
        matching: find.byType(Text),
      ),
    ))
      text.data!,
  ];

  Finder inTile(String id, Finder matching) => find.descendant(
    of: find.widgetWithText(TaskCard, 'Task $id'),
    matching: matching,
  );

  Future<void> choose(WidgetTester tester, String filter) async {
    final chip = find.descendant(
      of: find.byKey(const ValueKey('filters')),
      matching: find.text(filter),
    );
    // The bar scrolls: Done may be past the right edge.
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> swipe(
    WidgetTester tester,
    String id, {
    required bool right,
  }) async {
    await tester.drag(find.text('Task $id'), Offset(right ? 500 : -500, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('no tasks', (tester) async {
    await start(tester);

    expect(find.text('No tasks here'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('all active tasks in priority order with their day', (
    tester,
  ) async {
    await start(
      tester,
      tasks: [
        testTask('low', priority: 7),
        testTask('mid', priority: 3, minute: 1),
        testTask('high', priority: 2, minute: 2),
        testTask(
          'dated',
          priority: 3,
          dueDate: LocalDate(2026, 11, 20),
          minute: 3,
        ),
      ],
    );

    expect(tiles(tester), ['Task high', 'Task dated', 'Task mid', 'Task low']);
    expect(inTile('high', find.text('Planned for today')), findsOneWidget);
    expect(inTile('mid', find.text('Planned for Sat, Nov 14')), findsOneWidget);
    expect(inTile('dated', find.text('Due Fri, Nov 20')), findsOneWidget);
    expect(inTile('low', find.text('Low')), findsOneWidget);
  });

  testWidgets('a large task that waits for room says so (D21)', (tester) async {
    await start(
      tester,
      tasks: [
        testTask('L').copyWith(weight: 4),
        testTask('n', priority: 7, minute: 1),
      ],
    );

    expect(inTile('L', find.text('Planned for Sat, Nov 14')), findsOneWidget);
    expect(inTile('L', find.text('Waits for a day with room')), findsOneWidget);
    expect(inTile('L', find.text('Large')), findsOneWidget);
    expect(inTile('n', find.text('Waits for a day with room')), findsNothing);
  });

  testWidgets('done tasks are not listed', (tester) async {
    final app = await start(tester, tasks: [testTask('a'), testTask('b')]);
    await app.real(
      () => app.container
          .read(taskRepositoryProvider)
          .complete('a', AppHarness.now, onPlan: false),
    );
    await tester.pumpAndSettle();

    expect(tiles(tester), ['Task b']);
  });

  group('filters', () {
    final tasks = [
      testTask('a', priority: 1),
      testTask('focused', priority: 2, isFocused: true, minute: 1),
      testTask('due', priority: 3, dueDate: LocalDate(2026, 11, 20), minute: 2),
      testTask(
        'overdue',
        priority: 4,
        dueDate: LocalDate(2026, 11, 10),
        minute: 3,
      ),
      testTask('far', priority: 5, minute: 4),
    ];
    // Friday 1 + Saturday 3 fit four tasks; the fifth does not fit two days.
    final settings = Settings(planningHorizonDays: 2);

    testWidgets('Later: tasks that do not fit the horizon', (tester) async {
      await start(tester, tasks: tasks, settings: settings);
      expect(tiles(tester), hasLength(5));
      expect(inTile('far', find.text('Later')), findsOneWidget);

      await choose(tester, 'Later');

      expect(tiles(tester), ['Task far']);
    });

    testWidgets('Focus: focused and overdue tasks', (tester) async {
      await start(tester, tasks: tasks, settings: settings);

      await choose(tester, 'Focus');

      expect(tiles(tester), ['Task focused', 'Task overdue']);
      expect(inTile('overdue', find.text('Overdue by 3 days')), findsOneWidget);
    });

    testWidgets('With due date, and back to Active', (tester) async {
      await start(tester, tasks: tasks, settings: settings);

      await choose(tester, 'With due date');
      expect(tiles(tester), ['Task due', 'Task overdue']);

      await choose(tester, 'Active');
      expect(tiles(tester), hasLength(5));
    });

    testWidgets('each filter counts its active tasks; Done has no count '
        '(D22)', (tester) async {
      await start(tester, tasks: tasks, settings: settings);

      expect(find.text('5 active'), findsOneWidget);
      expect(chip(tester, 'active'), ['Active', '5']);
      expect(chip(tester, 'focus'), ['Focus', '2']);
      expect(chip(tester, 'due'), ['With due date', '2']);
      expect(chip(tester, 'recurring'), ['Recurring', '0']);
      expect(chip(tester, 'later'), ['Later', '1']);
      expect(chip(tester, 'done'), ['Done']);
      // Done is the last chip.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('filter-done'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('filter-later'))).dx,
        ),
      );
    });

    testWidgets('a filter without matches says so', (tester) async {
      await start(tester, tasks: [testTask('a')]);

      await choose(tester, 'Later');

      expect(find.text('No tasks here'), findsOneWidget);
    });
  });

  group('done tasks stay until the filter or the tab changes (D22)', () {
    testWidgets('Done keeps the card, the counts change at once', (
      tester,
    ) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );
      expect(find.text('2 active'), findsOneWidget);

      await tester.tap(inTile('b', find.byType(TaskDoneButton)));
      await tester.pumpAndSettle();

      expect(tiles(tester), ['Task a']);
      expect(doneTiles(tester), ['Task b']);
      expect(find.text('1 active'), findsOneWidget);
      expect(chip(tester, 'active'), ['Active', '1']);
      expect(find.text('Undo'), findsNothing);
      expect((await app.task('b')).isDone, isTrue);

      // Back and forth while the filter is shown.
      await tester.tap(inTile('b', find.text('Completed')));
      await tester.pumpAndSettle();
      expect(tiles(tester), ['Task a', 'Task b']);
      expect(find.text('2 active'), findsOneWidget);
      await tester.tap(inTile('b', find.byType(TaskDoneButton)));
      await tester.pumpAndSettle();
      expect(doneTiles(tester), ['Task b']);
    });

    testWidgets('another filter drops it', (tester) async {
      await start(tester, tasks: [testTask('a'), testTask('b', minute: 1)]);
      await tester.tap(inTile('a', find.byType(TaskDoneButton)));
      await tester.pumpAndSettle();
      expect(doneTiles(tester), ['Task a']);

      await choose(tester, 'Focus');
      await choose(tester, 'Active');

      expect(doneTiles(tester), isEmpty);
      expect(tiles(tester), ['Task b']);
    });

    testWidgets('another tab drops it', (tester) async {
      await start(tester, tasks: [testTask('a'), testTask('b', minute: 1)]);
      await tester.tap(inTile('a', find.byType(TaskDoneButton)));
      await tester.pumpAndSettle();
      expect(doneTiles(tester), ['Task a']);

      await tester.tap(find.byIcon(Icons.today_outlined).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();

      expect(doneTiles(tester), isEmpty);
      expect(tiles(tester), ['Task b']);
    });
  });

  group('swipes', () {
    testWidgets('right completes; from today\'s list it uses the slot', (
      tester,
    ) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );

      await swipe(tester, 'a', right: true);

      expect(tiles(tester), ['Task b']);
      expect(doneTiles(tester), ['Task a']);
      expect((await app.task('a')).completedOnPlan, isTrue);
      // The slot of today stays empty.
      expect(inTile('b', find.text('Planned for Sat, Nov 14')), findsOneWidget);
      expect(find.text('Undo'), findsNothing);

      await tester.tap(inTile('a', find.text('Completed')));
      await tester.pumpAndSettle();
      expect(tiles(tester), ['Task a', 'Task b']);
    });

    testWidgets('right on a task of another day leaves today as it is', (
      tester,
    ) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );

      await swipe(tester, 'b', right: true);

      expect(tiles(tester), ['Task a']);
      final done = await app.task('b');
      expect(done.isDone, isTrue);
      expect(done.completedOnPlan, isFalse);
    });

    testWidgets('left sets and clears the Focus mark', (tester) async {
      final app = await start(tester, tasks: [testTask('a')]);

      await swipe(tester, 'a', right: false);
      expect((await app.task('a')).isFocused, isTrue);
      expect(find.text('Added to Focus'), findsOneWidget);
      expect(tiles(tester), ['Task a']);
      expect(
        inTile('a', find.byIcon(Icons.center_focus_strong_outlined)),
        findsOne,
      );

      await swipe(tester, 'a', right: false);
      expect((await app.task('a')).isFocused, isFalse);
      expect(find.text('Removed from Focus'), findsOneWidget);
    });
  });

  testWidgets('Done completes, a tap opens the menu with Edit (D22)', (
    tester,
  ) async {
    final app = await start(tester, tasks: [testTask('a'), testTask('b')]);

    await tester.tap(inTile('a', find.byType(TaskDoneButton)));
    await tester.pumpAndSettle();
    expect((await app.task('a')).isDone, isTrue);
    // The "Undo" snack bar lies over the menu until it goes.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await openEditorOf(tester, find.text('Task b'));
    final editor = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
    expect(editor.taskId, 'b');
  });

  group('Done (T-306)', () {
    /// Completes a stored task at the given local time.
    Future<void> completeAt(AppHarness app, String id, DateTime at) => app.real(
      () => app.container
          .read(taskRepositoryProvider)
          .complete(id, at, onPlan: false),
    );

    /// Header and task texts of the Done list, top to bottom.
    List<String> rows(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byType(ListView), matching: find.byType(Text)),
      ))
        // Leave out the priority chip, the completion line and the button.
        if (text.data != 'Normal' && !text.data!.startsWith('Completed'))
          text.data!,
    ];

    testWidgets('completed tasks by day, the latest first', (tester) async {
      final app = await start(
        tester,
        tasks: [
          for (final id in ['a', 'b', 'c', 'd', 'e']) testTask(id),
        ],
      );
      await completeAt(app, 'a', DateTime(2026, 11, 13, 9, 30));
      await completeAt(app, 'b', DateTime(2026, 11, 13, 8));
      await completeAt(app, 'c', DateTime(2026, 11, 12, 20));
      await completeAt(app, 'd', DateTime(2026, 11, 10, 12));
      await tester.pumpAndSettle();

      await choose(tester, 'Done');

      expect(rows(tester), [
        'Today',
        'Task a',
        'Task b',
        'Yesterday',
        'Task c',
        'Tue, Nov 10',
        'Task d',
      ]);
      expect(
        tester.widgetList<TaskCard>(find.byType(TaskCard)).map((c) => c.isDone),
        everyElement(isTrue),
      );
    });

    testWidgets('the day follows the day start hour (D15)', (tester) async {
      final app = await start(
        tester,
        tasks: [testTask('a')],
        settings: Settings(dayStartHour: 4),
      );
      // 02:00 by the calendar of today is still yesterday for the user.
      await completeAt(app, 'a', DateTime(2026, 11, 13, 2));
      await tester.pumpAndSettle();

      await choose(tester, 'Done');

      expect(rows(tester), ['Yesterday', 'Task a']);
      expect(find.text('Completed yesterday'), findsOneWidget);
    });

    testWidgets('unticking returns the task to the active ones', (
      tester,
    ) async {
      final app = await start(tester, tasks: [testTask('a')]);
      await completeAt(app, 'a', DateTime(2026, 11, 13, 9, 30));
      await tester.pumpAndSettle();
      await choose(tester, 'Done');

      await tester.tap(find.byType(TaskDoneButton));
      await tester.pumpAndSettle();

      expect(find.text('No tasks here'), findsOneWidget);
      expect((await app.task('a')).isDone, isFalse);
      await choose(tester, 'Active');
      expect(tiles(tester), ['Task a']);
    });

    testWidgets('a tap opens the editor', (tester) async {
      final app = await start(tester, tasks: [testTask('a')]);
      await completeAt(app, 'a', DateTime(2026, 11, 13, 9, 30));
      await tester.pumpAndSettle();
      await choose(tester, 'Done');

      await tester.tap(find.text('Task a'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
    });
  });

  testWidgets('in Ukrainian', (tester) async {
    await start(
      tester,
      tasks: [testTask('a')],
      stored: {'device.locale': 'uk'},
    );

    expect(find.text('1 активне'), findsOneWidget);
    expect(chip(tester, 'active'), ['Активні', '1']);
    expect(chip(tester, 'due'), ['З терміном', '0']);
    expect(chip(tester, 'recurring'), ['Регулярні', '0']);
    expect(chip(tester, 'done'), ['Виконані']);
    expect(find.text('Заплановано на сьогодні'), findsOneWidget);
  });
}
