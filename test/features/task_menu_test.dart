import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/shared/task_card.dart';

import 'app_harness.dart';

/// The task menu a tap on a card opens (D22): T-908, T-909.
void main() {
  final today = AppHarness.today;
  final monday = LocalDate(2026, 11, 16);

  Finder destination(int index) => find.byType(NavigationDestination).at(index);

  Future<void> goTo(WidgetTester tester, int tab) async {
    await tester.tap(destination(tab));
    await tester.pumpAndSettle();
  }

  Finder card(String id) => find.widgetWithText(TaskCard, 'Task $id');

  /// Opens the menu of [id] on the Tasks tab, where every active task is.
  Future<void> openOnTasks(WidgetTester tester, String id) async {
    await goTo(tester, 2);
    await openMenuOf(tester, card(id));
  }

  /// "Postpone until…", the [day] of November, OK.
  Future<void> postpone(WidgetTester tester, int day) async {
    await tester.tap(find.byKey(const ValueKey('menuDefer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$day'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu closes when its tab is left (T-908)', (tester) async {
    await AppHarness.start(tester, tasks: [testTask('a')]);
    await openMenuOf(tester, card('a'));
    expect(find.text('Pin to a day…'), findsOneWidget);

    await goTo(tester, 1);
    expect(find.text('Pin to a day…'), findsNothing);

    await goTo(tester, 0);
    expect(find.text('Pin to a day…'), findsNothing);
    expect(card('a'), findsOneWidget);
  });

  group('postpone until (T-909)', () {
    testWidgets('keeps the task off Today; Tasks shows "From"', (tester) async {
      final app = await AppHarness.start(tester, tasks: [testTask('a')]);
      await openMenuOf(tester, card('a'));
      expect(find.text('Postpone until…'), findsOneWidget);
      // Not postponed: nothing to cancel.
      expect(find.text('Cancel postponement'), findsNothing);

      await postpone(tester, 16);

      expect((await app.task('a')).notBefore, monday);
      expect(card('a'), findsNothing);
      await goTo(tester, 2);
      expect(
        find.descendant(of: card('a'), matching: find.text('From Mon, Nov 16')),
        findsOneWidget,
      );
    });

    testWidgets('a pin before the day goes, a pin after it stays', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        tasks: [
          testTask('early', pinnedDate: today.addDays(1)),
          testTask('late', pinnedDate: LocalDate(2026, 11, 20), minute: 1),
        ],
      );

      await openOnTasks(tester, 'early');
      await postpone(tester, 16);
      await openMenuOf(tester, card('late'));
      await postpone(tester, 16);

      final early = await app.task('early');
      expect(early.notBefore, monday);
      expect(early.pinnedDate, isNull);
      final late = await app.task('late');
      expect(late.notBefore, monday);
      expect(late.pinnedDate, LocalDate(2026, 11, 20));
    });

    testWidgets('"Cancel postponement" makes it available now', (tester) async {
      final app = await AppHarness.start(
        tester,
        tasks: [testTask('a').copyWith(notBefore: monday)],
      );
      expect(card('a'), findsNothing);

      await openOnTasks(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('menuDeferClear')));
      await tester.pumpAndSettle();

      expect((await app.task('a')).notBefore, isNull);
      await goTo(tester, 0);
      expect(card('a'), findsOneWidget);
    });

    testWidgets('the picker ends at the due date', (tester) async {
      final app = await AppHarness.start(
        tester,
        tasks: [testTask('a', dueDate: LocalDate(2026, 11, 18))],
      );

      await openMenuOf(tester, card('a'));
      // The 19th is past the due date: not selectable, the picker keeps
      // its first day, tomorrow.
      await postpone(tester, 19);

      expect((await app.task('a')).notBefore, today.addDays(1));
    });

    testWidgets('not offered for a task due today', (tester) async {
      await AppHarness.start(tester, tasks: [testTask('a', dueDate: today)]);

      await openMenuOf(tester, card('a'));

      expect(find.text('Postpone until…'), findsNothing);
      expect(find.text('Pin to a day…'), findsOneWidget);
    });

    testWidgets('a repeating task moves its start', (tester) async {
      final weekly = testTask('a').setRecurrence(
        Recurrence.interval(every: 1, unit: RecurrenceUnit.week, anchor: today),
        today: today,
        now: AppHarness.now,
      );
      final app = await AppHarness.start(tester, tasks: [weekly]);

      await openOnTasks(tester, 'a');
      await postpone(tester, 16);

      final task = await app.task('a');
      expect(task.notBefore, monday);
      expect(task.occurrenceDate, monday);
      expect(
        (task.recurrence! as IntervalRecurrence).anchor,
        monday,
        reason: 'a rule by schedule is anchored on the new start',
      );
    });
  });
}
