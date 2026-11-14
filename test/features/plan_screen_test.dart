import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/shared/task_tile.dart';

import 'app_harness.dart';

void main() {
  final today = AppHarness.today;
  final saturday = LocalDate(2026, 11, 14);
  final monday = LocalDate(2026, 11, 16);

  /// Starts the app on a tall screen and opens the Plan tab.
  Future<AppHarness> start(
    WidgetTester tester, {
    List<Task> tasks = const [],
    Settings? settings,
    Map<String, Object> stored = const {},
  }) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      settings: settings,
      stored: stored,
    );
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    return app;
  }

  Finder header(LocalDate date) => find.byKey(ValueKey('day-${date.toIso()}'));

  /// The texts of a day header, for example ['Today', '1/1'].
  List<String> headerTexts(WidgetTester tester, LocalDate date) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: header(date), matching: find.byType(Text)),
    ))
      text.data ?? text.textSpan!.toPlainText(),
  ];

  /// Everything in the list, top to bottom: day headers by their date and
  /// tasks by their title.
  List<String> rows(WidgetTester tester) {
    final found = <(double, String)>[];
    for (final element in find.byType(InkWell).evaluate()) {
      final key = element.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('day-')) {
        found.add((
          tester.getTopLeft(find.byWidget(element.widget)).dy,
          key.value.substring(4),
        ));
      }
    }
    for (final tile in tester.widgetList<TaskTile>(find.byType(TaskTile))) {
      found.add((tester.getTopLeft(find.byWidget(tile)).dy, tile.task.title));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final row in found) row.$2];
  }

  Finder inTile(String id, Finder matching) => find.descendant(
    of: find.widgetWithText(TaskTile, 'Task $id'),
    matching: matching,
  );

  Future<DayOverride?> overrideOf(AppHarness app, LocalDate date) async =>
      (await app.real(
        () =>
            app.container.read(dayOverrideRepositoryProvider).watchAll().first,
      ))[date];

  group('days (T-401)', () {
    testWidgets('each day with its tasks, how full it is, and Later', (
      tester,
    ) async {
      await start(
        tester,
        tasks: [
          for (var i = 1; i <= 6; i++) testTask('t$i', priority: i, minute: i),
        ],
        // Friday, Saturday, Sunday (rest), Monday.
        settings: Settings(priorityScale: 10, planningHorizonDays: 4),
      );

      expect(rows(tester), [
        '2026-11-13',
        'Task t1',
        '2026-11-14',
        'Task t2',
        'Task t3',
        'Task t4',
        '2026-11-15',
        '2026-11-16',
        'Task t5',
        'Task t6',
      ]);
      expect(headerTexts(tester, today), ['Today', '1/1']);
      expect(headerTexts(tester, saturday), ['Tomorrow', '3/3']);
      expect(headerTexts(tester, LocalDate(2026, 11, 15)), [
        'Sun, Nov 15',
        'Rest day',
      ]);
      expect(headerTexts(tester, monday), ['Mon, Nov 16', '1/1']);
      expect(find.text('Later (1)'), findsOneWidget);
      // "Later" is below the last day.
      expect(
        tester.getTopLeft(find.text('Later (1)')).dy,
        lessThan(tester.getTopLeft(find.text('Task t6')).dy),
      );
    });

    testWidgets('reason badges, an overloaded day and the at-risk banner', (
      tester,
    ) async {
      await start(
        tester,
        tasks: [
          testTask('d1', dueDate: today),
          testTask('d2', dueDate: today, minute: 1),
          testTask('d3', dueDate: today, minute: 2),
          testTask('p', pinnedDate: saturday, minute: 3),
        ],
      );

      expect(headerTexts(tester, today), ['Today', '2/1']);
      expect(
        find.descendant(
          of: header(today),
          matching: find.byIcon(Icons.error_outline),
        ),
        findsOneWidget,
      );
      expect(inTile('d1', find.text('Deadline')), findsOneWidget);
      expect(inTile('d2', find.text('Extra')), findsOneWidget);
      expect(inTile('d3', find.text('At risk')), findsOneWidget);
      expect(inTile('p', find.text('Pinned')), findsOneWidget);
      expect(find.text('1 task at risk'), findsOneWidget);
    });

    testWidgets('a task of a later day is completed ahead of time (D19)', (
      tester,
    ) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );

      await tester.tap(inTile('b', find.byType(Checkbox)));
      await tester.pumpAndSettle();

      expect((await app.task('b')).completedOnPlan, isFalse);
      expect(headerTexts(tester, today), ['Today', '1/1']);

      await tester.tap(inTile('a', find.byType(Checkbox)));
      await tester.pumpAndSettle();
      expect((await app.task('a')).completedOnPlan, isTrue);
      // Today still holds one task of its one: the done one counts, as on
      // the Today screen.
      expect(headerTexts(tester, today), ['Today', '1/1']);
    });

    testWidgets('a tap opens the editor', (tester) async {
      await start(tester, tasks: [testTask('a')]);

      await tester.tap(find.text('Task a'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
    });

    testWidgets('in Ukrainian', (tester) async {
      await start(
        tester,
        tasks: [testTask('a'), testTask('b')],
        settings: Settings(planningHorizonDays: 1),
        stored: {'device.locale': 'uk'},
      );

      expect(headerTexts(tester, today), ['Сьогодні', '1/1']);
      expect(find.text('Пізніше (1)'), findsOneWidget);
    });
  });

  group('pin from the plan (T-402)', () {
    testWidgets('a long press moves the task to a day, and unpins it', (
      tester,
    ) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );
      expect(rows(tester).take(4), [
        '2026-11-13',
        'Task a',
        '2026-11-14',
        'Task b',
      ]);

      await tester.longPress(find.text('Task b'));
      await tester.pumpAndSettle();
      expect(find.text('Unpin'), findsNothing);
      await tester.tap(find.text('Move to a day…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect((await app.task('b')).pinnedDate, monday);
      expect(rows(tester).skip(2).take(4), [
        '2026-11-14',
        '2026-11-15',
        '2026-11-16',
        'Task b',
      ]);
      expect(inTile('b', find.text('Pinned')), findsOneWidget);

      await tester.longPress(find.text('Task b'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin'));
      await tester.pumpAndSettle();

      expect((await app.task('b')).pinnedDate, isNull);
      expect(rows(tester).skip(2).take(2), ['2026-11-14', 'Task b']);
    });

    testWidgets('the menu opens the editor too', (tester) async {
      await start(tester, tasks: [testTask('a')]);

      await tester.longPress(find.text('Task a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
    });
  });

  group('capacity of one day (T-403)', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('set, with a note; the plan follows', (tester) async {
      final app = await start(
        tester,
        tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
      );

      await tester.tap(header(today));
      await tester.pumpAndSettle();
      expect(find.text('Tasks on Fri, Nov 13'), findsOneWidget);
      await tapKey(tester, 'override+');
      await tester.enterText(find.byType(TextField), ' Day off ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        await overrideOf(app, today),
        DayOverride(date: today, capacity: 2, note: 'Day off'),
      );
      expect(headerTexts(tester, today), ['Today  Day off', '2/2']);
      expect(rows(tester).take(3), ['2026-11-13', 'Task a', 'Task b']);
      expect(
        find.descendant(of: header(today), matching: find.byIcon(Icons.tune)),
        findsOneWidget,
      );
    });

    testWidgets('a rest day with a pinned task shows the count', (
      tester,
    ) async {
      await start(
        tester,
        tasks: [testTask('a', pinnedDate: LocalDate(2026, 11, 15))],
      );

      expect(headerTexts(tester, LocalDate(2026, 11, 15)), [
        'Sun, Nov 15',
        '1/0',
      ]);
    });

    testWidgets('down to a rest day, and back to the weekday', (tester) async {
      final app = await start(tester, tasks: [testTask('a')]);

      await tester.tap(header(today));
      await tester.pumpAndSettle();
      // A day without its own capacity has nothing to reset.
      expect(find.text('As the weekday'), findsNothing);
      await tapKey(tester, 'override-');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Rest day'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect((await overrideOf(app, today))!.capacity, 0);
      expect(rows(tester).take(3), ['2026-11-13', '2026-11-14', 'Task a']);

      await tester.tap(header(today));
      await tester.pumpAndSettle();
      await tester.tap(find.text('As the weekday'));
      await tester.pumpAndSettle();

      expect(await overrideOf(app, today), isNull);
      expect(rows(tester).take(2), ['2026-11-13', 'Task a']);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final app = await start(tester);

      await tester.tap(header(saturday));
      await tester.pumpAndSettle();
      await tapKey(tester, 'override+');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await overrideOf(app, saturday), isNull);
    });
  });

  group('at-risk tasks (T-404)', () {
    final dueToday = [
      testTask('d1', dueDate: today),
      testTask('d2', dueDate: today, minute: 1),
      testTask('d3', dueDate: today, minute: 2),
    ];

    /// Opens the list from the banner and the actions of the task at risk.
    Future<void> openActions(WidgetTester tester) async {
      await tester.tap(find.text('1 task at risk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('atRisk-d3')));
      await tester.pumpAndSettle();
    }

    testWidgets('a later due date clears the flag', (tester) async {
      final app = await start(tester, tasks: dueToday);

      await openActions(tester);
      await tester.tap(find.text('Move due date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect((await app.task('d3')).dueDate, monday);
      expect(find.textContaining('at risk'), findsNothing);
      // The list closed by itself: nothing is at risk.
      expect(find.byKey(const ValueKey('atRisk-d3')), findsNothing);
    });

    testWidgets('one more task today clears the flag', (tester) async {
      final app = await start(tester, tasks: dueToday);

      await openActions(tester);
      await tester.tap(find.text('One more task today'));
      await tester.pumpAndSettle();

      expect((await overrideOf(app, today))!.capacity, 2);
      expect(find.textContaining('at risk'), findsNothing);
      expect(headerTexts(tester, today), ['Today', '3/2']);
    });

    testWidgets('deleting the task clears the flag', (tester) async {
      final app = await start(tester, tasks: dueToday);

      await openActions(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect((await app.task('d3')).isDeleted, isTrue);
      expect(find.textContaining('at risk'), findsNothing);
    });

    testWidgets('the editor can be opened from there', (tester) async {
      await start(tester, tasks: dueToday);

      await openActions(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final editor = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(editor.taskId, 'd3');
    });
  });
}
