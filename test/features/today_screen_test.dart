import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/today/today_screen.dart';
import 'package:tasks_order/shared/task_tile.dart';

import 'app_harness.dart';

void main() {
  final today = AppHarness.today;
  final saturday = LocalDate(2026, 11, 14);

  /// The titles of the task tiles, top to bottom.
  List<String> tiles(WidgetTester tester) => [
    for (final tile in tester.widgetList<TaskTile>(find.byType(TaskTile)))
      tile.task.title,
  ];

  Finder tile(String id) => find.widgetWithText(TaskTile, 'Task $id');

  Finder inTile(String id, Finder matching) =>
      find.descendant(of: tile(id), matching: matching);

  Future<void> tick(WidgetTester tester, String id) async {
    await tester.tap(inTile(id, find.byType(Checkbox)));
    await tester.pumpAndSettle();
  }

  group('empty states', () {
    testWidgets('no tasks at all', (tester) async {
      await AppHarness.start(tester);

      expect(find.text('Nothing planned for today'), findsOneWidget);
      expect(find.text('Add tasks on the Tasks tab'), findsOneWidget);
      expect(find.byType(TaskTile), findsNothing);
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
          testTask('low', priority: 4),
          testTask('high', priority: 1, dueDate: LocalDate(2026, 11, 20)),
        ],
      );

      expect(tiles(tester), ['Task high']);
      expect(find.text('Planned 1/1'), findsOneWidget);
      expect(inTile('high', find.text('Critical (1)')), findsOneWidget);
      expect(inTile('high', find.text('Due Fri, Nov 20')), findsOneWidget);
      expect(find.textContaining('Done today'), findsNothing);
    });

    testWidgets('a priority slot is not refilled, undo gives it back', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );
      expect(tiles(tester), ['Task a']);

      await tick(tester, 'a');

      expect(tiles(tester), isEmpty);
      expect(find.text('Planned 0/1'), findsOneWidget);
      expect(find.text('Done today: 1'), findsOneWidget);
      expect(find.text('All done for today'), findsOneWidget);
      final done = await app.task('a');
      expect(done.isDone, isTrue);
      expect(done.completedOnPlan, isTrue);

      expect(find.text('Task completed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(tiles(tester), ['Task a']);
      expect((await app.task('a')).isDone, isFalse);
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
        find.text('More than planned: 2 tasks, capacity 1'),
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

      expect(inTile('p', find.text('Pinned')), findsOneWidget);
    });

    testWidgets('the reason badges can be switched off', (tester) async {
      await AppHarness.start(
        tester,
        tasks: [testTask('p', pinnedDate: today)],
        stored: {'device.showReasons': false},
      );

      expect(tiles(tester), ['Task p']);
      expect(find.text('Pinned'), findsNothing);
    });

    testWidgets('a tap on a task opens the editor', (tester) async {
      await AppHarness.start(tester, tasks: [testTask('a')]);

      await tester.tap(find.text('Task a'));
      await tester.pumpAndSettle();

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
      expect(find.text('Focus'), findsOneWidget);
      expect(inTile('f', find.text('Planned for Sat, Nov 14')), findsOneWidget);
      expect(inTile('f', find.byIcon(Icons.center_focus_strong)), findsOne);
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

      expect(tiles(tester), ['Task a']);
      expect(find.text('Planned 1/1'), findsOneWidget);
      expect(find.textContaining('Done today'), findsNothing);
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
      // Not overdue: no menu.
      expect(
        inTile('a', find.byType(PopupMenuButton<VoidCallback>)),
        findsNothing,
      );

      await tester.tap(inTile('o', find.byType(PopupMenuButton<VoidCallback>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove due date'));
      await tester.pumpAndSettle();

      expect(tiles(tester), ['Task a']);
      expect(find.text('Focus'), findsNothing);
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

      await tester.tap(inTile('o', find.byType(PopupMenuButton<VoidCallback>)));
      await tester.pumpAndSettle();
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
      expect(find.text('+2 more'), findsOneWidget);
    });
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
    expect(find.text('Фокус'), findsOneWidget);
    expect(find.text('Прострочено на 5 днів'), findsOneWidget);
    expect(find.text('Заплановано 2/1'), findsOneWidget);
    expect(find.text('Термін сьогодні'), findsNWidgets(2));
    expect(find.text('Дедлайн'), findsNWidgets(2));
    expect(find.text('1 завдання не встигне до терміну'), findsOneWidget);
    expect(find.textContaining('Заплановано на'), findsWidgets);
  });
}
