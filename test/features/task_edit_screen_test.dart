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
}
