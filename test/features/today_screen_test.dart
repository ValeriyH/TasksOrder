import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/today/today_screen.dart';
import 'package:tasks_order/shared/screen_header.dart';
import 'package:tasks_order/shared/task_card.dart';

import 'app_harness.dart';

void main() {
  final today = AppHarness.today;
  final saturday = LocalDate(2026, 11, 14);

  /// The titles of the active task cards, top to bottom.
  List<String> tiles(WidgetTester tester) => [
    for (final card in tester.widgetList<TaskCard>(find.byType(TaskCard)))
      if (!card.isDone) card.task.title,
  ];

  /// The section titles, the cards and the empty state, top to bottom:
  /// where a card sits.
  List<String> layout(WidgetTester tester) => [
    for (final widget in tester.widgetList(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byWidgetPredicate(
          (w) =>
              w is TaskCard ||
              w is SectionHeader ||
              w.key == const ValueKey('emptyDay'),
        ),
      ),
    ))
      switch (widget) {
        TaskCard(:final task, :final isDone) =>
          isDone ? '${task.title} (done)' : task.title,
        SectionHeader(:final title, :final counter) => '$title $counter',
        // The empty state of the day (T-910).
        _ => 'empty',
      },
  ];

  Finder tile(String id) => find.widgetWithText(TaskCard, 'Task $id');

  Finder inTile(String id, Finder matching) =>
      find.descendant(of: tile(id), matching: matching);

  Future<void> tick(WidgetTester tester, String id) async {
    await tester.tap(inTile(id, find.byType(TaskDoneButton)));
    await tester.pumpAndSettle();
  }

  group('empty states', () {
    testWidgets('no tasks at all', (tester) async {
      await AppHarness.start(tester);

      expect(find.text('Nothing planned for today'), findsOneWidget);
      expect(find.text('Add tasks on the Tasks tab'), findsOneWidget);
      expect(find.byType(TaskCard), findsNothing);
      // A card under the Planned header, which has no counter (T-910).
      expect(layout(tester), ['Planned null', 'empty']);
    });

    testWidgets('tasks exist, but none for today', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [testTask('a')],
        settings: Settings(weeklyCapacity: const [1, 1, 1, 1, 0, 3, 0]),
      );

      expect(find.text('Nothing planned for today'), findsOneWidget);
      expect(find.text('Add tasks on the Tasks tab'), findsNothing);
    });
  });

  group('today\'s list', () {
    testWidgets('shows the tasks the plan puts on today', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('low', priority: 7),
          testTask('high', priority: 2, dueDate: LocalDate(2026, 11, 20)),
        ],
      );

      expect(layout(tester), ['Planned 0/1', 'Task high']);
      expect(find.text('Friday, 13 November'), findsOneWidget);
      expect(find.text('0 of 1'), findsOneWidget);
      expect(inTile('high', find.text('Critical')), findsOneWidget);
      expect(inTile('high', find.text('Due Fri, Nov 20')), findsOneWidget);
    });

    testWidgets('a done task stays at the end, its slot is not refilled, '
        '"Completed" gives it back (D22)', (tester) async {
      final app = await AppHarness.start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );
      expect(tiles(tester), ['Task a']);

      await tick(tester, 'a');

      // "All done" above the tasks done today (T-910).
      expect(layout(tester), ['Planned 1/1', 'empty', 'Task a (done)']);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.text('All done for today'), findsOneWidget);
      expect(inTile('a', find.text('Completed')), findsOneWidget);
      // The card undoes: no message with Undo.
      expect(find.text('Task completed'), findsNothing);
      final done = await app.task('a');
      expect(done.isDone, isTrue);
      expect(done.completedOnPlan, isTrue);

      await tester.tap(inTile('a', find.text('Completed')));
      await tester.pumpAndSettle();

      expect(layout(tester), ['Planned 0/1', 'Task a']);
      expect((await app.task('a')).isDone, isFalse);
    });

    testWidgets('done tasks go after the ones left', (tester) async {
      await AppHarness.start(
        tester,
        settings: Settings(weeklyCapacity: const [3, 3, 3, 3, 3, 3, 3]),
        tasks: [
          testTask('a', priority: 1),
          testTask('b', priority: 2),
          testTask('c', priority: 3),
        ],
      );

      await tick(tester, 'a');
      await tick(tester, 'c');

      expect(layout(tester), [
        'Planned 2/3',
        'Task b',
        'Task a (done)',
        'Task c (done)',
      ]);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('header and banner count the done tasks with the rest', (
      tester,
    ) async {
      // Friday holds 2, deadlines may add 2: four due today all fit.
      await AppHarness.start(
        tester,
        settings: Settings(
          weeklyCapacity: const [1, 1, 1, 1, 2, 3, 0],
          maxOverflowPerDay: 2,
        ),
        tasks: [
          for (var i = 1; i <= 4; i++)
            testTask('d$i', dueDate: today, minute: i),
        ],
      );
      expect(find.text('0 of 4'), findsOneWidget);
      expect(
        find.text('More than planned: 4 of 2 slots taken'),
        findsOneWidget,
      );

      await tick(tester, 'd1');

      // One done of the four the day holds; still four against two.
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(
        find.text('More than planned: 4 of 2 slots taken'),
        findsOneWidget,
      );
    });

    testWidgets('a deadline slot is refilled (D16)', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('d1', dueDate: today),
          testTask('d2', dueDate: today, minute: 1),
          testTask('d3', dueDate: today, minute: 2),
        ],
      );

      // Capacity 1 + overflow 1: two today, the third will be late.
      expect(tiles(tester), ['Task d1', 'Task d2']);
      expect(inTile('d1', find.text('Deadline')), findsOneWidget);
      expect(inTile('d1', find.text('Due today')), findsOneWidget);
      expect(inTile('d2', find.text('Extra')), findsOneWidget);
      expect(
        find.text('More than planned: 2 of 1 slots taken'),
        findsOneWidget,
      );
      expect(find.text('1 task will not make its deadline'), findsOneWidget);

      await tick(tester, 'd1');

      expect(tiles(tester), ['Task d2', 'Task d3']);
      expect(find.textContaining('will not make'), findsNothing);
    });

    testWidgets(
      'the at-risk banner opens the list, a task offers the ways out',
      (tester) async {
        await AppHarness.start(
          tester,
          tasks: [
            testTask('d1', dueDate: today),
            testTask('d2', dueDate: today, minute: 1),
            testTask('d3', dueDate: today, minute: 2),
            testTask('d4', dueDate: today, minute: 3),
          ],
        );

        await tester.tap(find.text('2 tasks will not make their deadline'));
        await tester.pumpAndSettle();
        expect(find.text('At risk'), findsOneWidget);
        expect(find.text('Task d4'), findsOneWidget);

        // A task offers the ways out; one of them is the editor (T-404).
        await tester.tap(find.text('Task d3'));
        await tester.pumpAndSettle();
        expect(find.text('Move due date'), findsOneWidget);
        expect(find.text('One more task today'), findsOneWidget);
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();

        final editor = tester.widget<TaskEditScreen>(
          find.byType(TaskEditScreen),
        );
        expect(editor.taskId, 'd3');
      },
    );

    testWidgets('a pinned task has its badge', (tester) async {
      await AppHarness.start(tester, tasks: [testTask('p', pinnedDate: today)]);

      expect(inTile('p', find.text('Pinned to Fri, Nov 13')), findsOneWidget);
    });

    testWidgets('in Focus the pin chip has no date: the planned chip has it '
        '(T-911)', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1),
          testTask('p', pinnedDate: today.addDays(1), isFocused: true),
        ],
      );

      expect(inTile('p', find.text('Pinned')), findsOneWidget);
      expect(inTile('p', find.text('Planned for Sat, Nov 14')), findsOneWidget);
    });

    testWidgets('the reason badges can be switched off', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('d1', dueDate: today),
          testTask('d2', dueDate: today, minute: 1),
          testTask('d3', dueDate: today, minute: 2),
        ],
        stored: {'device.showReasons': false},
      );

      // The scenario of "deadlines are forced" without its reason chips.
      expect(tiles(tester), ['Task d1', 'Task d2']);
      expect(find.text('Deadline'), findsNothing);
      expect(find.text('Extra'), findsNothing);
    });

    testWidgets('a tap opens the menu, and Edit the editor (D22)', (
      tester,
    ) async {
      await AppHarness.start(tester, tasks: [testTask('a')]);

      await openEditorOf(tester, find.text('Task a'));

      expect(find.text('Edit task'), findsOneWidget);
    });
  });

  group('Focus (D17, D18)', () {
    testWidgets('shows focused tasks of other days with their day', (
      tester,
    ) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1, isFocused: true),
          testTask('f', priority: 2, isFocused: true),
        ],
      );

      // Focus first, then today's list. "a" is on today's list, so it is not
      // repeated in Focus.
      expect(tiles(tester), ['Task f', 'Task a']);
      expect(find.text('FOCUS'), findsOneWidget);
      expect(inTile('f', find.text('Planned for Sat, Nov 14')), findsOneWidget);
      // Today has its Focus section: no focus chip on the cards (D22).
      expect(
        inTile('f', find.byIcon(Icons.center_focus_strong_outlined)),
        findsNothing,
      );
    });

    testWidgets('a completion from Focus leaves today\'s list as it is (D19)', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1),
          testTask('f', priority: 2, isFocused: true),
        ],
      );

      await tick(tester, 'f');

      // Done from Focus: it stays there, today's list is as it was (D19).
      expect(layout(tester), [
        // The counter is the tasks still in Focus (owner, D22).
        'Focus 0',
        'Task f (done)',
        'Planned 0/1',
        'Task a',
      ]);
      expect(find.text('0 of 1'), findsOneWidget);
      expect(inTile('f', find.text('Completed today')), findsOneWidget);
      expect((await app.task('f')).completedOnPlan, isFalse);
    });

    testWidgets('an overdue task is there with its badge and actions', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1),
          testTask('o', priority: 4, dueDate: LocalDate(2026, 11, 10)),
        ],
      );

      expect(tiles(tester), ['Task o', 'Task a']);
      expect(inTile('o', find.text('Overdue by 3 days')), findsOneWidget);
      // Not overdue: no due date actions in the menu.
      await openMenuOf(tester, find.text('Task a'));
      expect(find.byKey(const ValueKey('menuClearDue')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await openMenuOf(tester, find.text('Task o'));
      await tester.tap(find.text('Remove due date'));
      await tester.pumpAndSettle();

      expect(tiles(tester), ['Task a']);
      expect(find.text('FOCUS'), findsNothing);
      expect((await app.task('o')).dueDate, isNull);
    });

    testWidgets('moving the due date of an overdue task plans it again', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1),
          testTask('o', priority: 4, dueDate: LocalDate(2026, 11, 12)),
        ],
      );
      expect(inTile('o', find.text('Overdue by 1 day')), findsOneWidget);

      await openMenuOf(tester, find.text('Task o'));
      await tester.tap(find.text('Move due date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('14'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect((await app.task('o')).dueDate, saturday);
      // Planned for Saturday by its date, no longer in Focus.
      expect(tiles(tester), ['Task a']);
    });

    testWidgets('shows three and counts the rest', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [
          testTask('a', priority: 1),
          for (var i = 1; i <= 5; i++)
            testTask('f$i', priority: 2, isFocused: true, minute: i),
        ],
      );

      expect(tiles(tester), ['Task f1', 'Task f2', 'Task f3', 'Task a']);
      // The counter is all five; the list shows three and the rest.
      expect(layout(tester).first, 'Focus 5');
      expect(find.text('+2 more'), findsOneWidget);
    });
  });

  testWidgets('the lists of the tabs start below the status bar (D22)', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 72);
    addTearDown(tester.view.resetPadding);
    await AppHarness.start(tester, tasks: [testTask('a')]);
    final top = 72 / tester.view.devicePixelRatio;

    for (final tab in [
      Icons.today_outlined,
      Icons.calendar_month_outlined,
      Icons.checklist_outlined,
    ]) {
      await tester.tap(find.byIcon(tab).last);
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).hitTestable().first;
      expect(tester.getTopLeft(list).dy, greaterThanOrEqualTo(top));
    }
  });

  testWidgets('in Ukrainian and dark', (tester) async {
    await AppHarness.start(
      tester,
      tasks: [
        testTask('a', priority: 1),
        testTask('o', priority: 4, dueDate: LocalDate(2026, 11, 8)),
        testTask('d', dueDate: today, minute: 1),
        testTask('d2', dueDate: today, minute: 2),
        testTask('d3', dueDate: today, minute: 3),
      ],
      stored: {'device.locale': 'uk', 'device.themeMode': 'dark'},
    );

    expect(
      Theme.of(tester.element(find.byType(TodayScreen))).brightness,
      Brightness.dark,
    );
    expect(find.text('ФОКУС'), findsOneWidget);
    expect(find.text('Прострочено на 5 днів'), findsOneWidget);
    expect(find.text('ЗАПЛАНОВАНО'), findsOneWidget);
    expect(find.text('0 з 2'), findsOneWidget);
    expect(find.textContaining('13 листопада'), findsOneWidget);
    expect(find.text('Термін сьогодні'), findsNWidgets(2));
    expect(find.text('Дедлайн'), findsNWidgets(2));
    expect(find.text('1 завдання не встигне до терміну'), findsOneWidget);
    expect(find.textContaining('Заплановано на'), findsWidgets);
  });
}
