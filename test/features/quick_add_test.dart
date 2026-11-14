import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/today/quick_add_sheet.dart';
import 'package:tasks_order/shared/task_tile.dart';

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
    expect(task.createdAt, AppHarness.now.toUtc());
    expect(find.widgetWithText(TaskTile, 'Buy milk'), findsOneWidget);
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

  testWidgets('ticking a task gives haptic feedback', (tester) async {
    await AppHarness.start(tester, tasks: [testTask('a')]);
    final haptics = recordHaptics(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('in Ukrainian', (tester) async {
    await AppHarness.start(tester, stored: {'device.locale': 'uk'});
    await open(tester);

    expect(find.text('Назва'), findsOneWidget);
    expect(find.text('Додати'), findsOneWidget);
    expect(find.text('Звичайний'), findsOneWidget);
  });
}
