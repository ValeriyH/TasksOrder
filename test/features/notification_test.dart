import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/repository/prefs_device_settings_repository.dart';
import 'package:tasks_order/domain/model/task.dart';

import 'app_harness.dart';

/// The morning notification (T-501). The harness day is Friday 13 November,
/// 10:00, with Friday capacity 1, Saturday 3 and Sunday a rest day.
void main() {
  final tasks = [
    for (final (i, id) in 'abcd'.split('').indexed) testTask(id, minute: i),
  ];
  const timeKey = PrefsDeviceSettingsRepository.notificationTimeKey;

  Future<AppHarness> start(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    FakeNotificationScheduler? notifications,
  }) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      stored: stored,
      notifications: notifications,
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('notificationSwitch')));
    await tester.pumpAndSettle();
  }

  testWidgets('off by default: nothing is pending', (tester) async {
    final app = await start(tester);

    expect(find.text('Morning notification'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(app.notifications.pending, isEmpty);
    expect(app.notifications.channelName, 'Morning plan');
  });

  testWidgets('switching on asks for the permission and schedules the week', (
    tester,
  ) async {
    final app = await start(tester);

    await toggle(tester);

    expect(app.notifications.permissionRequests, 1);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(timeKey), 8 * 60);
    expect(find.textContaining('8:00'), findsOneWidget);
    // Friday 08:00 is past; Saturday has b, c and d; Sunday is a rest day
    // and nothing is left for the days after it.
    final pending = app.notifications.pending.single;
    expect(pending.id, 20261114);
    expect(pending.at, DateTime(2026, 11, 14, 8));
    expect(pending.title, 'Today: 3 tasks');
    expect(pending.lines, ['Task b', 'Task c', 'Task d']);
  });

  testWidgets('a refused permission leaves it off with a hint', (tester) async {
    final app = await start(
      tester,
      notifications: FakeNotificationScheduler(grant: false),
    );

    await toggle(tester);

    expect(find.textContaining('not allowed'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(app.notifications.pending, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(timeKey), isFalse);
  });

  testWidgets('switching off cancels what is pending', (tester) async {
    final app = await start(tester, stored: {timeKey: 8 * 60});
    expect(app.notifications.pending, isNotEmpty);

    await toggle(tester);

    expect(app.notifications.pending, isEmpty);
    expect(find.text('Off'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(timeKey), isFalse);
  });

  testWidgets('a change of the plan reschedules', (tester) async {
    final app = await start(tester, stored: {timeKey: 8 * 60});
    expect(app.notifications.pending.single.lines.first, 'Task b');

    // A more important task takes Friday and moves a to Saturday.
    final urgent = Task.create(
      id: 'e',
      title: 'Task e',
      priority: 1,
      now: AppHarness.now,
    );
    await app.real(
      () => app.container
          .read(taskRepositoryProvider)
          .upsert(urgent, AppHarness.now),
    );
    await tester.pumpAndSettle();

    // Saturday has a, b and c now; d moved on to Monday.
    expect(app.notifications.pending.map((n) => n.lines), [
      ['Task a', 'Task b', 'Task c'],
      ['Task d'],
    ]);
  });

  testWidgets('the texts follow the language of the app', (tester) async {
    final app = await start(
      tester,
      stored: {timeKey: 8 * 60, 'device.locale': 'uk'},
    );

    expect(find.text('Ранкове сповіщення'), findsOneWidget);
    expect(app.notifications.pending.single.title, 'Сьогодні: 3 завдання');
    expect(app.notifications.channelName, 'План на ранок');
  });

  testWidgets('a tap on the row opens the time picker', (tester) async {
    await start(tester, stored: {timeKey: 8 * 60});

    await tester.tap(find.text('Morning notification'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(timeKey), 8 * 60);
  });
}
