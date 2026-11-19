import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';

import 'app_harness.dart';

/// T-707: the "Repeat" row of the editor and its sheet. The harness day is
/// Friday 13 November 2026.
void main() {
  final today = AppHarness.today;

  Future<AppHarness> start(WidgetTester tester, {List<Task> tasks = const []}) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return AppHarness.start(tester, tasks: tasks);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) =>
      tap(tester, find.byKey(ValueKey(key)));

  /// The Tasks tab, then the editor of a new task with [title].
  Future<void> openNew(WidgetTester tester, String title) async {
    await tap(tester, find.byIcon(Icons.checklist_outlined));
    await tap(tester, find.byType(FloatingActionButton));
    await tester.enterText(find.byType(TextFormField).first, title);
    await tester.pump();
  }

  Future<void> openExisting(WidgetTester tester, String title) async {
    await tap(tester, find.byIcon(Icons.checklist_outlined));
    await openEditorOf(tester, find.text(title));
  }

  Future<void> save(WidgetTester tester) => tap(tester, find.text('Save'));

  Future<Task> storedByTitle(AppHarness app, String title) async {
    final all = await app.real(
      () => app.container.read(taskRepositoryProvider).watchAll().first,
    );
    return all.singleWhere((t) => t.title == title);
  }

  String repeatRow(WidgetTester tester) {
    final tile = tester.widget<ListTile>(find.byKey(const ValueKey('repeat')));
    final text = tile.subtitle! as Text;
    return text.data ?? text.textSpan!.toPlainText();
  }

  Task recurring(String id, Recurrence rule, {LocalDate? due}) =>
      testTask(id)
          .copyWith(dueDate: due)
          .setRecurrence(rule, today: today, now: AppHarness.now);

  group('create', () {
    testWidgets('every 2 weeks by schedule', (tester) async {
      final app = await start(tester);
      await openNew(tester, 'Clean');
      expect(repeatRow(tester), 'Does not repeat');

      await tapKey(tester, 'repeat');
      await tap(tester, find.text('Every N'));
      await tapKey(tester, 'repeatEvery+');
      await tapKey(tester, 'repeatDone');

      expect(repeatRow(tester), startsWith('Every 2 weeks\n'));
      expect(
        repeatRow(tester),
        endsWith('Comes back on each date of the rule'),
      );
      await save(tester);
      final task = await storedByTitle(app, 'Clean');
      expect(
        task.recurrence,
        Recurrence.interval(every: 2, unit: RecurrenceUnit.week, anchor: today),
      );
      expect(task.seriesId, task.id);
      expect(task.occurrenceDate, today);
    });

    testWidgets('days after it is done', (tester) async {
      final app = await start(tester);
      await openNew(tester, 'Haircut');

      await tapKey(tester, 'repeat');
      await tap(tester, find.text('Every N'));
      await tapKey(tester, 'repeatUnit');
      await tap(tester, find.text('day').last);
      await tapKey(tester, 'repeatEvery+');
      await tapKey(tester, 'repeatEvery+');
      await tapKey(tester, 'repeatAfterDone');
      await tapKey(tester, 'repeatDone');

      expect(repeatRow(tester), startsWith('3 days after it is done'));
      await save(tester);
      expect(
        (await storedByTitle(app, 'Haircut')).recurrence,
        Recurrence.interval(
          every: 3,
          unit: RecurrenceUnit.day,
          afterDone: true,
        ),
      );
    });

    testWidgets('weekdays', (tester) async {
      final app = await start(tester);
      await openNew(tester, 'Gym');

      await tapKey(tester, 'repeat');
      await tap(tester, find.text('Weekdays'));
      // Friday, today's weekday, is chosen already.
      await tapKey(tester, 'repeatDay0');
      await tapKey(tester, 'repeatDay2');
      await tapKey(tester, 'repeatDone');

      expect(repeatRow(tester), startsWith('Mon, Wed, Fri'));
      await save(tester);
      expect(
        (await storedByTitle(app, 'Gym')).recurrence,
        Recurrence.weekdays(const {0, 2, 4}),
      );
    });

    testWidgets('the hint follows the dates of the task', (tester) async {
      await start(tester);
      await openNew(tester, 'Rent');
      await tapKey(tester, 'repeat');
      await tap(tester, find.text('Every N'));
      await tapKey(tester, 'repeatDone');

      // Pinned to today with the shortcut.
      await tap(tester, find.text('Today').last);
      expect(repeatRow(tester), endsWith('Pinned on each date of the rule'));
    });

    testWidgets('cancel keeps what was there', (tester) async {
      await start(tester);
      await openNew(tester, 'Nothing');

      await tapKey(tester, 'repeat');
      await tap(tester, find.text('Weekdays'));
      await tap(tester, find.text('Cancel'));

      expect(repeatRow(tester), 'Does not repeat');
    });
  });

  testWidgets('change a rule', (tester) async {
    final weekly = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.week,
      anchor: today,
    );
    final app = await start(tester, tasks: [recurring('w', weekly)]);
    await openExisting(tester, 'Task w');
    expect(repeatRow(tester), startsWith('Every week'));

    await tapKey(tester, 'repeat');
    await tapKey(tester, 'repeatUnit');
    await tap(tester, find.text('month').last);
    await tapKey(tester, 'repeatDone');
    await save(tester);

    final task = await app.task('w');
    expect((task.recurrence! as IntervalRecurrence).unit, RecurrenceUnit.month);
    expect(task.seriesId, 'w');
  });

  testWidgets('remove a rule: an ordinary task of its series', (tester) async {
    final app = await start(
      tester,
      tasks: [
        recurring('w', Recurrence.weekdays(const {0})),
      ],
    );
    await openExisting(tester, 'Task w');

    await tapKey(tester, 'repeat');
    await tap(tester, find.text('No'));
    await tapKey(tester, 'repeatDone');
    expect(repeatRow(tester), 'Does not repeat');
    await save(tester);

    final task = await app.task('w');
    expect(task.recurrence, isNull);
    expect(task.occurrenceDate, isNull);
    expect(task.seriesId, 'w');
  });

  testWidgets('a new due date moves the anchor', (tester) async {
    final monthly = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.month,
      anchor: today,
    );
    final app = await start(
      tester,
      tasks: [recurring('m', monthly, due: LocalDate(2026, 11, 20))],
    );
    await openExisting(tester, 'Task m');

    await tap(tester, find.text('Due date'));
    await tap(tester, find.text('27'));
    await tap(tester, find.text('OK'));
    await save(tester);

    final task = await app.task('m');
    expect(task.dueDate, LocalDate(2026, 11, 27));
    expect(task.occurrenceDate, LocalDate(2026, 11, 27));
    expect(
      (task.recurrence! as IntervalRecurrence).anchor,
      LocalDate(2026, 11, 27),
    );
  });

  testWidgets('a save without a new rule or date keeps the anchor', (
    tester,
  ) async {
    // The successor of "monthly from Oct 31": due Nov 30, anchor Oct 31.
    final monthly = Recurrence.interval(
      every: 1,
      unit: RecurrenceUnit.month,
      anchor: LocalDate(2026, 10, 31),
    );
    final stored = testTask('m').copyWith(
      dueDate: LocalDate(2026, 11, 30),
      recurrence: monthly,
      seriesId: 'm0',
      occurrenceDate: LocalDate(2026, 11, 30),
    );
    final app = await start(tester, tasks: [stored]);
    await openExisting(tester, 'Task m');

    await tester.enterText(find.byType(TextFormField).first, 'Pay rent');
    await save(tester);

    final task = await app.task('m');
    expect(task.title, 'Pay rent');
    expect(task.recurrence, monthly);
    expect(task.seriesId, 'm0');
  });
}
