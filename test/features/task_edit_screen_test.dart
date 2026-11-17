import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/app/app.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/model/task_size.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/tasks/tasks_screen.dart';
import 'package:tasks_order/shared/priority_dropdown.dart';

import '../data/test_database.dart';

void main() {
  // A Friday, 10:00 local time.
  final now = DateTime(2026, 11, 13, 10);
  final today = LocalDate(2026, 11, 13);

  late ProviderContainer container;
  late TaskRepository tasks;

  /// Runs a database call of the test itself outside the fake clock of the
  /// widget test, where it would never complete.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      await tester.runAsync(body) as T;

  /// Starts the app on an empty in-memory database.
  Future<void> pumpApp(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    Settings? settings,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    // The editor is taller than the default test window since the size
    // row (D21): keep every field built and on screen.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    tasks = container.read(taskRepositoryProvider);
    if (settings != null) {
      await real(
        tester,
        () => container.read(settingsRepositoryProvider).save(settings, now),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TasksOrderApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the editor for a new task from the Tasks tab.
  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  /// Stores a task and opens the editor on it.
  Future<Task> openExisting(WidgetTester tester, Task task) async {
    await real(tester, () => tasks.upsert(task, task.createdAt));
    unawaited(container.read(routerProvider).push(AppRoutes.task(task.id)));
    await tester.pumpAndSettle();
    return task;
  }

  Future<List<Task>> stored(WidgetTester tester) =>
      real(tester, () => tasks.watchAll().first);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// A priority name in the priority field; "Normal" is a size too (D21).
  Finder inPriority(String name) => find.descendant(
    of: find.byType(PriorityDropdown),
    matching: find.text(name),
  );

  group('new task', () {
    testWidgets('title and the default priority are enough', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      expect(find.text('New task'), findsOneWidget);
      expect(inPriority('Normal'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // The keyboard is ready for the title.
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.enterText(field('Title'), '  Buy milk ');
      await save(tester);

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);
      final task = (await stored(tester)).single;
      expect(task.title, 'Buy milk');
      expect(task.notes, isNull);
      expect(task.priority, PriorityLabels.normal);
      expect(task.dueDate, isNull);
      expect(task.pinnedDate, isNull);
      expect(task.isFocused, isFalse);
      expect(task.createdAt, now.toUtc());
    });

    testWidgets('an empty title is not saved', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      await tester.enterText(field('Title'), '   ');
      await save(tester);

      expect(find.text('Enter a title'), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('all fields are stored', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      await tester.enterText(field('Title'), 'Tax return');
      await tester.enterText(field('Notes'), 'Form 3');

      await tester.tap(inPriority('Normal'));
      await tester.pumpAndSettle();
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Someday'), findsOneWidget);
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();

      // The picker opens on today; a tap on the 20th chooses that day.
      await tester.tap(find.text('Due date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Focus'));
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.title, 'Tax return');
      expect(task.notes, 'Form 3');
      expect(task.priority, 3);
      expect(task.dueDate, LocalDate(2026, 11, 20));
      expect(task.pinnedDate, today);
      expect(task.isFocused, isTrue);
      expect(task.focusedAt, now.toUtc());
    });

    testWidgets('the priorities follow the scale of the settings', (
      tester,
    ) async {
      await pumpApp(tester, settings: Settings(priorityScale: 10));
      await openNew(tester);

      expect(inPriority('Normal'), findsOneWidget);
      await tester.tap(inPriority('Normal'));
      await tester.pumpAndSettle();
      expect(find.text('Catastrophic'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
    });

    testWidgets('in Ukrainian', (tester) async {
      await pumpApp(tester, stored: {'device.locale': 'uk'});
      await openNew(tester);

      expect(find.text('Нове завдання'), findsOneWidget);
      expect(find.text('Звичайний'), findsOneWidget);
      expect(find.text('Кінцевий термін'), findsOneWidget);
      expect(find.text('Не вказано'), findsNWidgets(2));
      expect(find.text('Зберегти'), findsOneWidget);
    });
  });

  group('existing task', () {
    final created = DateTime(2026, 11, 10, 8);

    Task sample() => Task.create(
      id: 'a',
      title: 'Call the bank',
      notes: 'Ask about the card',
      priority: 3,
      dueDate: LocalDate(2026, 11, 18),
      isFocused: true,
      now: created,
    ).copyWith(pinnedDate: LocalDate(2026, 11, 16));

    testWidgets('the fields show the stored values', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, sample());

      expect(find.text('Edit task'), findsOneWidget);
      expect(find.text('Call the bank'), findsOneWidget);
      expect(find.text('Ask about the card'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Wednesday, November 18, 2026'), findsOneWidget);
      expect(find.text('Monday, November 16, 2026'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      // No keyboard until the user asks for it.
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('changes are saved, the rest of the task is kept', (
      tester,
    ) async {
      await pumpApp(tester);
      final before = await openExisting(tester, sample());

      await tester.enterText(field('Title'), 'Call the bank again');
      await tester.enterText(field('Notes'), '');
      // Clears the due date and the pin, in this order on the screen.
      await tester.tap(find.byTooltip('Clear').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Focus'));
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.id, before.id);
      expect(task.title, 'Call the bank again');
      expect(task.notes, isNull);
      expect(task.priority, 3);
      expect(task.dueDate, isNull);
      expect(task.pinnedDate, isNull);
      expect(task.isFocused, isFalse);
      expect(task.focusedAt, isNull);
      expect(task.createdAt, created.toUtc());
      expect(task.updatedAt, now.toUtc());
    });

    testWidgets('saving without changes keeps the Focus time', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, sample());

      await save(tester);

      expect((await stored(tester)).single.focusedAt, created.toUtc());
    });

    testWidgets('a level the scale does not offer shows as the nearest one '
        'and is kept on save', (tester) async {
      await pumpApp(tester, settings: Settings(priorityScale: 3));
      await openExisting(
        tester,
        Task.create(id: 'b', title: 'Old', priority: 9, now: created),
      );

      expect(find.text('Low'), findsOneWidget);
      await save(tester);

      expect((await stored(tester)).single.priority, 9);
    });

    testWidgets('delete moves the task to the Trash, undo brings it back', (
      tester,
    ) async {
      await pumpApp(tester);
      await openExisting(tester, sample());

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.text('Moved to Trash'), findsOneWidget);
      expect(await stored(tester), isEmpty);
      expect((await real(tester, () => tasks.getById('a')))!.isDeleted, isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect((await stored(tester)).single.id, 'a');
    });

    testWidgets('an unknown or deleted task is reported', (tester) async {
      await pumpApp(tester);
      unawaited(container.read(routerProvider).push(AppRoutes.task('nope')));
      await tester.pumpAndSettle();

      expect(find.text('Task not found'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });

  group('size (D21, T-805)', () {
    Finder segment(String label) => find.descendant(
      of: find.byKey(const ValueKey('size')),
      matching: find.text(label),
    );

    bool selected(WidgetTester tester, TaskSize size) => tester
        .widget<SegmentedButton<TaskSize>>(find.byKey(const ValueKey('size')))
        .selected
        .contains(size);

    testWidgets('a new task is normal; a size picked is stored', (
      tester,
    ) async {
      await pumpApp(tester);
      await openNew(tester);
      expect(selected(tester, TaskSize.normal), isTrue);
      expect(
        find.text(
          'Small: two share one slot of a day. Large: takes two slots.',
        ),
        findsOneWidget,
      );

      await tester.enterText(field('Title'), 'Roof');
      await tester.tap(segment('Large'));
      await tester.pumpAndSettle();
      expect(selected(tester, TaskSize.large), isTrue);
      await save(tester);

      expect((await stored(tester)).single.weight, 4);
    });

    testWidgets('a new task saved as it is weighs 2', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await tester.enterText(field('Title'), 'Call');
      await save(tester);

      expect((await stored(tester)).single.weight, 2);
    });

    testWidgets('changing the size of a task', (tester) async {
      await pumpApp(tester);
      await openExisting(
        tester,
        Task.create(
          id: 'a',
          title: 'Bills',
          priority: 5,
          now: now,
        ).copyWith(weight: 4),
      );
      expect(selected(tester, TaskSize.large), isTrue);

      await tester.tap(segment('Small'));
      await tester.pumpAndSettle();
      await save(tester);

      expect((await stored(tester)).single.weight, 1);
    });

    testWidgets('an unknown weight is kept unless a size is picked', (
      tester,
    ) async {
      await pumpApp(tester);
      await openExisting(
        tester,
        Task.create(
          id: 'a',
          title: 'Odd',
          priority: 5,
          now: now,
        ).copyWith(weight: 3),
      );
      // 3 reads as the nearest size, the larger on a tie.
      expect(selected(tester, TaskSize.large), isTrue);

      await tester.enterText(field('Title'), 'Odd one');
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.title, 'Odd one');
      expect(task.weight, 3);
    });

    testWidgets('in Ukrainian', (tester) async {
      await pumpApp(tester, stored: {'device.locale': 'uk'});
      await openNew(tester);

      expect(find.text('Розмір'), findsOneWidget);
      expect(segment('Маленька'), findsOneWidget);
      expect(segment('Звичайна'), findsOneWidget);
      expect(segment('Велика'), findsOneWidget);
    });
  });

  group('not before (T-714)', () {
    Finder notBefore() => find.byKey(const ValueKey('notBefore'));

    Future<void> pickNotBefore(WidgetTester tester, String day) async {
      await tester.tap(notBefore());
      await tester.pumpAndSettle();
      await tester.tap(find.text(day));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('set: stored, off Today, "From" on the card', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await tester.enterText(field('Title'), 'Renew the passport');
      expect(
        find.textContaining(
          'Kept off the plan until this day, then planned by priority',
          findRichText: true,
        ),
        findsOneWidget,
      );

      await pickNotBefore(tester, '20');
      expect(
        find.textContaining('Friday, November 20, 2026', findRichText: true),
        findsOneWidget,
      );
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.notBefore, LocalDate(2026, 11, 20));
      // The Tasks tab: "From" the day; Today does not have it.
      expect(find.text('From Fri, Nov 20'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.today_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Renew the passport'), findsNothing);
    });

    testWidgets('clear', (tester) async {
      await pumpApp(tester);
      await openExisting(
        tester,
        Task.create(
          id: 'n',
          title: 'Later',
          priority: PriorityLabels.normal,
          now: now,
        ).copyWith(notBefore: LocalDate(2026, 11, 20)),
      );

      await tester.tap(
        find.descendant(of: notBefore(), matching: find.byTooltip('Clear')),
      );
      await tester.pumpAndSettle();
      await save(tester);

      expect((await stored(tester)).single.notBefore, isNull);
    });

    testWidgets('a due date before it is refused with a hint', (tester) async {
      await pumpApp(tester);
      await openExisting(
        tester,
        Task.create(
          id: 'n',
          title: 'Later',
          priority: PriorityLabels.normal,
          dueDate: LocalDate(2026, 11, 18),
          now: now,
        ),
      );

      await pickNotBefore(tester, '20');
      await save(tester);

      expect(
        find.textContaining(
          'The due date is before this day',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect((await stored(tester)).single.notBefore, isNull);

      // A later due date makes it right.
      await tester.tap(find.text('Due date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.notBefore, LocalDate(2026, 11, 20));
      expect(task.dueDate, LocalDate(2026, 11, 25));
    });

    testWidgets('a pin before it is allowed: the pin leads', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await tester.enterText(field('Title'), 'Early');
      await pickNotBefore(tester, '20');
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.pinnedDate, today);
      expect(task.notBefore, LocalDate(2026, 11, 20));
      // Pinned on today: no "From" on the card.
      expect(find.textContaining('From '), findsNothing);
    });

    testWidgets('on a repeat from completion it moves the date of the '
        'repeat', (tester) async {
      await pumpApp(tester);
      final rule = Recurrence.interval(
        every: 10,
        unit: RecurrenceUnit.day,
        afterDone: true,
      );
      await openExisting(
        tester,
        Task.create(
              id: 'h',
              title: 'Haircut',
              priority: PriorityLabels.normal,
              now: now,
            )
            .copyWith(notBefore: LocalDate(2026, 11, 20))
            .setRecurrence(rule, today: today, now: now),
      );

      await pickNotBefore(tester, '25');
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.notBefore, LocalDate(2026, 11, 25));
      expect(task.occurrenceDate, LocalDate(2026, 11, 25));
      expect(task.recurrence, rule);
    });
  });

  // Today is Friday 2026-11-13; the week is 1 slot on working days, 3 on
  // Saturday, Sunday is a rest day.
  group('days (D23, T-1005)', () {
    Finder daysRow() => find.byKey(const ValueKey('days'));
    Finder inRow(String text) =>
        find.descendant(of: daysRow(), matching: find.textContaining(text));

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(daysRow());
      await tester.pumpAndSettle();
    }

    Future<void> toggle(WidgetTester tester, List<int> days) async {
      for (final day in days) {
        await tester.tap(find.byKey(ValueKey('allowedDay$day')));
        await tester.pump();
      }
    }

    Future<void> done(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('daysDone')));
      await tester.pumpAndSettle();
    }

    Task existing(Set<int>? days, {LocalDate? due, LocalDate? pin}) =>
        Task.create(
          id: 'd',
          title: 'Hand in the papers',
          priority: PriorityLabels.normal,
          dueDate: due,
          now: now,
        ).copyWith(pinnedDate: pin, allowedWeekdays: days);

    testWidgets('set: stored, the chip on the card, off Today', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await tester.enterText(field('Title'), 'Change the tyres');
      expect(inRow('Any day'), findsOneWidget);

      await openSheet(tester);
      expect(find.text('Days of the week'), findsOneWidget);
      await toggle(tester, [5]);
      await done(tester);

      expect(inRow('Sat'), findsOneWidget);
      expect(inRow('Planned only on these days of the week'), findsOneWidget);
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.allowedWeekdays, {5});
      // The Tasks tab: the chip and tomorrow, a Saturday.
      expect(find.text('Only Sat'), findsOneWidget);
      expect(find.textContaining('Sat, Nov 14'), findsOneWidget);
      // Today is a Friday: not there.
      await tester.tap(find.byIcon(Icons.today_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Change the tyres'), findsNothing);
    });

    testWidgets('several days read in the order of the week', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await tester.enterText(field('Title'), 'Papers');

      await openSheet(tester);
      await toggle(tester, [4, 3]);
      await done(tester);

      expect(inRow('Thu, Fri'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, {3, 4});
      expect(find.text('Only Thu, Fri'), findsOneWidget);
    });

    testWidgets('change: the sheet starts from the stored days', (
      tester,
    ) async {
      await pumpApp(tester);
      await openExisting(tester, existing({3, 4}));
      expect(inRow('Thu, Fri'), findsOneWidget);

      await openSheet(tester);
      // Thursday off, Saturday on.
      await toggle(tester, [3, 5]);
      await done(tester);

      expect(inRow('Fri, Sat'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, {4, 5});
    });

    testWidgets('cancel keeps the days', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({5}));

      await openSheet(tester);
      await toggle(tester, [0, 1]);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(inRow('Sat'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, {5});
    });

    testWidgets('clear with the button of the row', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({5}));

      await tester.tap(
        find.descendant(of: daysRow(), matching: find.byIcon(Icons.close)),
      );
      await tester.pump();

      expect(inRow('Any day'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, isNull);
    });

    testWidgets('"Any day" in the sheet clears the choice', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({3, 4}));

      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('daysAny')));
      await tester.pump();
      await done(tester);

      expect(inRow('Any day'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, isNull);
    });

    testWidgets('all seven days are stored as any day', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({5}));

      await openSheet(tester);
      await toggle(tester, [0, 1, 2, 3, 4, 6]);
      await done(tester);

      expect(inRow('Any day'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, isNull);
    });

    testWidgets('hint: the pin is on another day, and the save goes '
        'through', (tester) async {
      await pumpApp(tester);
      // Pinned to Monday the 16th, only Saturdays.
      await openExisting(tester, existing({5}, pin: LocalDate(2026, 11, 16)));

      expect(inRow('Pinned to another day: the pin leads'), findsOneWidget);
      await save(tester);

      final task = (await stored(tester)).single;
      expect(task.allowedWeekdays, {5});
      expect(task.pinnedDate, LocalDate(2026, 11, 16));
    });

    testWidgets('no hint when the pin is on a chosen day', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({5}, pin: LocalDate(2026, 11, 14)));

      expect(inRow('Planned only on these days of the week'), findsOneWidget);
    });

    testWidgets('hint: only rest days', (tester) async {
      await pumpApp(tester);
      await openExisting(tester, existing({6}));

      expect(
        inRow('These are rest days: the task will not get into the plan'),
        findsOneWidget,
      );
      // A working day next to it is enough.
      await openSheet(tester);
      await toggle(tester, [5]);
      await done(tester);
      expect(inRow('Planned only on these days of the week'), findsOneWidget);
    });

    testWidgets('hint: no chosen day before the due date', (tester) async {
      await pumpApp(tester);
      // Due on Monday the 16th: Fri, Sat, Sun, Mon hold no Thursday.
      await openExisting(tester, existing({3}, due: LocalDate(2026, 11, 16)));

      expect(inRow('No such day before the due date'), findsOneWidget);
      await save(tester);
      expect((await stored(tester)).single.allowedWeekdays, {3});
    });

    testWidgets('no hint when a chosen day comes before the due date', (
      tester,
    ) async {
      await pumpApp(tester);
      await openExisting(tester, existing({3}, due: LocalDate(2026, 11, 19)));

      expect(inRow('Planned only on these days of the week'), findsOneWidget);
    });

    testWidgets('a repeating task keeps the days on its next repeat', (
      tester,
    ) async {
      await pumpApp(tester);
      final rule = Recurrence.interval(
        every: 1,
        unit: RecurrenceUnit.week,
        anchor: today,
      );
      final task = await openExisting(
        tester,
        existing({5}).setRecurrence(rule, today: today, now: now),
      );

      await tester.enterText(field('Title'), 'Clean the flat');
      await save(tester);
      await real(
        tester,
        () => tasks.complete(task.id, now, onPlan: false, today: today),
      );

      final next = (await stored(tester)).singleWhere((t) => !t.isDone);
      expect(next.id, task.successorId);
      expect(next.title, 'Clean the flat');
      expect(next.allowedWeekdays, {5});
    });

    testWidgets('in Ukrainian', (tester) async {
      await pumpApp(tester, stored: {'device.locale': 'uk'});
      await openExisting(tester, existing({3, 4}));

      expect(find.text('Дні'), findsOneWidget);
      expect(inRow('Чт, Пт'), findsOneWidget);
      expect(inRow('Планується лише в ці дні тижня'), findsOneWidget);
      await openSheet(tester);
      expect(find.text('Дні тижня'), findsOneWidget);
      expect(find.text('Будь-який день'), findsOneWidget);
    });
  });
}
