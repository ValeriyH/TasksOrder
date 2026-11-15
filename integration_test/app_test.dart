import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/app/app.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/notifications.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/repository/notification_scheduler.dart';
import 'package:tasks_order/shared/task_card.dart';

/// The happy path of T-504 on a device or emulator:
///
///     flutter test integration_test -d emulator-5554
///
/// The app runs with its real platform code and plugins, but on an
/// in-memory database and empty preferences, so the data of an installed
/// app is never touched; the notifications are a no-op so no permission
/// dialog of the system stops the test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add a task, edit it, complete it, find it among the done', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'device.locale': 'en'});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(db),
        notificationSchedulerProvider.overrideWithValue(_NoNotifications()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    // Every day takes tasks, whatever weekday the test runs on.
    await container
        .read(settingsRepositoryProvider)
        .save(
          Settings(weeklyCapacity: const [3, 3, 3, 3, 3, 3, 3]),
          DateTime.now(),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TasksOrderApp(),
      ),
    );
    await pumpUntil(tester, find.text('Nothing planned for today'));

    // Quick add from Today.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Buy milk');
    // The button turns on with the next frame.
    await tester.pump();
    await tester.tap(find.text('Add'));
    await pumpUntil(tester, find.text('0 of 1'));
    expect(find.text('Buy milk'), findsOneWidget);

    // Open the editor through the task menu (D22), rename, save.
    await tester.tap(find.text('Buy milk'));
    await pumpUntil(tester, find.byKey(const ValueKey('menuEdit')));
    await tester.tap(find.byKey(const ValueKey('menuEdit')));
    await pumpUntil(tester, find.text('Edit task'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Buy milk'),
      'Buy oat milk',
    );
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, find.text('Buy oat milk'));
    expect(find.text('Edit task'), findsNothing);

    // Complete it: today is done.
    await tester.tap(find.byType(TaskDoneButton));
    await pumpUntil(tester, find.text('All done for today'));

    // The Tasks tab lists it among the done ones.
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Buy oat milk'), findsNothing);
    // The filter chips scroll sideways; on a phone Done is off screen.
    final done = find.byKey(const ValueKey('filter-done'));
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    await tester.tap(done);
    await pumpUntil(tester, find.text('Buy oat milk'));
  });
}

/// Pumps until [finder] finds exactly one widget: on a device the database
/// answers in real time, which `pumpAndSettle` does not wait for.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pumpAndSettle();
    if (finder.evaluate().length == 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

class _NoNotifications implements NotificationScheduler {
  @override
  bool get isSupported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replacePending(
    List<ScheduledNotification> notifications, {
    required String channelName,
  }) async {}
}
