import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/trash/trash_screen.dart';
import 'package:tasks_order/shared/task_tile.dart';

import 'app_harness.dart';

void main() {
  /// Starts the app with [deleted] (id → time of deletion) already in the
  /// Trash and opens the Trash from the Tasks tab.
  Future<AppHarness> start(
    WidgetTester tester, {
    List<Task> tasks = const [],
    Map<String, DateTime> deleted = const {},
    Map<String, Object> stored = const {},
    bool open = true,
  }) async {
    final app = await AppHarness.start(
      tester,
      tasks: [
        ...tasks,
        for (final MapEntry(key: id, value: at) in deleted.entries)
          testTask(id).trash(at),
      ],
      stored: stored,
    );
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    if (open) {
      await tester.tap(find.byTooltip(stored.isEmpty ? 'Trash' : 'Кошик'));
      await tester.pumpAndSettle();
    }
    return app;
  }

  Future<Task?> stored(AppHarness app, String id) => app.real<Task?>(
    () => app.container.read(taskRepositoryProvider).getById(id),
  );

  /// The titles in the Trash, top to bottom.
  List<String> titles(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(
        of: find.byType(TrashScreen),
        matching: find.byType(ListTile),
      ),
    ))
      (tile.title! as Text).data!,
  ];

  testWidgets('empty', (tester) async {
    await start(tester);

    expect(find.byType(TrashScreen), findsOneWidget);
    expect(find.text('The Trash is empty'), findsOneWidget);
  });

  testWidgets('deleted tasks, the latest first, with the day of deletion', (
    tester,
  ) async {
    await start(
      tester,
      tasks: [testTask('active')],
      deleted: {
        'old': DateTime(2026, 11, 2, 9),
        'new': DateTime(2026, 11, 12, 9),
      },
    );

    expect(titles(tester), ['Task new', 'Task old']);
    expect(find.text('Deleted Thu, Nov 12'), findsOneWidget);
    expect(find.text('Deleted Mon, Nov 2'), findsOneWidget);
    expect(
      find.text('Deleted tasks are removed for good after 30 days'),
      findsOneWidget,
    );
  });

  testWidgets('restore returns the task to the plan', (tester) async {
    final app = await start(tester, deleted: {'a': DateTime(2026, 11, 12, 9)});

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('The Trash is empty'), findsOneWidget);
    expect((await stored(app, 'a'))!.isDeleted, isFalse);

    // Back to the tabs: the task is planned for today again.
    app.container.read(routerProvider).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.today_outlined));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TaskTile, 'Task a'), findsOneWidget);
  });

  testWidgets('delete forever asks first', (tester) async {
    final app = await start(tester, deleted: {'a': DateTime(2026, 11, 12, 9)});

    await tester.tap(find.byTooltip('Delete forever'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete "Task a" forever? This cannot be undone.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await stored(app, 'a'), isNotNull);

    await tester.tap(find.byTooltip('Delete forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
    await tester.pumpAndSettle();

    expect(await stored(app, 'a'), isNull);
    expect(find.text('The Trash is empty'), findsOneWidget);
  });

  testWidgets('what was deleted more than 30 days ago is gone at start', (
    tester,
  ) async {
    final app = await start(
      tester,
      deleted: {
        // The harness day is 13 November.
        'long ago': DateTime(2026, 10, 13, 9),
        'recent': DateTime(2026, 10, 15, 9),
      },
    );

    expect(titles(tester), ['Task recent']);
    expect(await stored(app, 'long ago'), isNull);
  });

  testWidgets('in Ukrainian', (tester) async {
    await start(
      tester,
      deleted: {'a': DateTime(2026, 11, 12, 9)},
      stored: {'device.locale': 'uk'},
    );

    expect(find.text('Кошик'), findsOneWidget);
    expect(find.byTooltip('Відновити'), findsOneWidget);
    expect(find.byTooltip('Видалити назавжди'), findsOneWidget);
  });
}
