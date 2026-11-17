import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/today/quick_add_sheet.dart';
import 'package:tasks_order/shared/task_card.dart';

import 'app_harness.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  Future<List<Task>> stored(AppHarness app) => app.real(
    () => app.container.read(taskRepositoryProvider).watchAll().first,
  );

  bool addEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  /// Records the haptic feedback the app asks the platform for.
  List<String> recordHaptics(WidgetTester tester) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return calls;
  }

  testWidgets('type a title, press Add: the task is on Today', (tester) async {
    final app = await AppHarness.start(tester);
    final haptics = recordHaptics(tester);

    await open(tester);
    // Ready to type, nothing to add yet.
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.text('Normal'), findsOneWidget);
    expect(addEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), ' Buy milk ');
    await tester.pump();
    expect(addEnabled(tester), isTrue);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddSheet), findsNothing);
    final task = (await stored(app)).single;
    expect(task.title, 'Buy milk');
    expect(task.priority, PriorityLabels.normal);
    // The chip "Today" is off by default (T-1102).
    expect(task.pinnedDate, isNull);
    expect(task.createdAt, AppHarness.now.toUtc());
    expect(find.widgetWithText(TaskCard, 'Buy milk'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('the keyboard action adds the task too', (tester) async {
    final app = await AppHarness.start(tester);
    await open(tester);

    await tester.enterText(find.byType(TextField), 'Call mum');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(QuickAddSheet), findsNothing);
    expect((await stored(app)).single.title, 'Call mum');
  });

  testWidgets('a blank title adds nothing', (tester) async {
    final app = await AppHarness.start(tester);
    await open(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(addEnabled(tester), isFalse);
    expect(find.byType(QuickAddSheet), findsOneWidget);
    expect(await stored(app), isEmpty);
  });

  testWidgets('the priority can be chosen, from the scale of the settings', (
    tester,
  ) async {
    final app = await AppHarness.start(
      tester,
      settings: Settings(priorityScale: 3),
    );
    await open(tester);
    expect(find.text('Normal'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Fix the tap');
    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    // Scale 3 offers Critical, Normal and Low only.
    expect(find.text('High'), findsNothing);
    await tester.tap(find.text('Critical').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect((await stored(app)).single.priority, 2);
  });

  group('pin to today and the full editor (T-1102)', () {
    testWidgets('the chip "Today" pins the new task to today', (tester) async {
      final app = await AppHarness.start(
        tester,
        // Today is full: only the pin brings the new task there.
        tasks: [testTask('a', priority: 1)],
        settings: Settings(priorityScale: 5),
      );
      await open(tester);

      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.tap(find.byKey(const ValueKey('quickAddPinToday')));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('quickAddPinToday')))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final task = (await stored(app))
          .singleWhere((task) => task.title == 'Buy milk');
      expect(task.pinnedDate, AppHarness.today);
      expect(find.widgetWithText(TaskCard, 'Buy milk'), findsOneWidget);
    });

    testWidgets('the full editor gets what was typed and saves it', (
      tester,
    ) async {
      final app = await AppHarness.start(
        tester,
        settings: Settings(priorityScale: 3),
      );
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Fix the tap');
      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Critical').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quickAddPinToday')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quickAddFullEditor')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddSheet), findsNothing);
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(find.text('New task'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TaskEditScreen),
          matching: find.text('Fix the tap'),
        ),
        findsOneWidget,
      );
      // Nothing is stored before the editor saves.
      expect(await stored(app), isEmpty);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final task = (await stored(app)).single;
      expect(task.title, 'Fix the tap');
      expect(task.priority, 2);
      expect(task.pinnedDate, AppHarness.today);
    });

    testWidgets('leaving the full editor stores nothing', (tester) async {
      final app = await AppHarness.start(tester);
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Call mum');

      await tester.tap(find.byKey(const ValueKey('quickAddFullEditor')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(await stored(app), isEmpty);
    });

    testWidgets('the full editor without a title starts empty', (tester) async {
      await AppHarness.start(tester);
      await open(tester);

      await tester.tap(find.byKey(const ValueKey('quickAddFullEditor')));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find
                  .descendant(
                    of: find.byType(TaskEditScreen),
                    matching: find.byType(TextField),
                  )
                  .first,
            )
            .controller!
            .text,
        isEmpty,
      );
    });
  });

  testWidgets('ticking a task gives haptic feedback', (tester) async {
    await AppHarness.start(tester, tasks: [testTask('a')]);
    final haptics = recordHaptics(tester);

    await tester.tap(find.byType(TaskDoneButton));
    await tester.pumpAndSettle();

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('in Ukrainian', (tester) async {
    await AppHarness.start(tester, stored: {'device.locale': 'uk'});
    await open(tester);

    expect(find.text('Назва'), findsOneWidget);
    expect(find.text('Додати'), findsOneWidget);
    expect(find.text('Звичайний'), findsOneWidget);
    expect(find.text('На сьогодні'), findsOneWidget);
    expect(find.byTooltip('Повний редактор'), findsOneWidget);
  });
}
