import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/app/app.dart';
import 'package:tasks_order/application/backup.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/home_widget.dart';
import 'package:tasks_order/application/notifications.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/backup_repository.dart';
import 'package:tasks_order/domain/repository/home_screen_widget.dart';
import 'package:tasks_order/domain/repository/notification_scheduler.dart';

import '../data/test_database.dart';

/// The whole app on an in-memory database with a fixed clock, for widget
/// tests of the screens.
class AppHarness {
  AppHarness._(
    this.tester,
    this.container,
    this.notifications,
    this.homeWidget,
  );

  final WidgetTester tester;
  final ProviderContainer container;

  /// Stands in for the notifications of the device.
  final FakeNotificationScheduler notifications;

  /// Stands in for the home-screen widget.
  final FakeHomeScreenWidget homeWidget;

  /// A Friday, 10:00 local time. Default capacity: Friday 1, Saturday 3,
  /// Sunday 0; overflow 1.
  static final now = DateTime(2026, 11, 13, 10);
  static final today = LocalDate(2026, 11, 13);

  /// Stores [settings] and [tasks], then starts the app and waits for the
  /// first screen. [stored] are the SharedPreferences of the device;
  /// [backupFiles] stands in for the file dialogs.
  static Future<AppHarness> start(
    WidgetTester tester, {
    List<Task> tasks = const [],
    Settings? settings,
    Map<String, Object> stored = const {},
    BackupFileStore? backupFiles,
    FakeNotificationScheduler? notifications,
  }) async {
    final scheduler = notifications ?? FakeNotificationScheduler();
    final homeWidget = FakeHomeScreenWidget();
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => now),
        notificationSchedulerProvider.overrideWithValue(scheduler),
        homeScreenWidgetProvider.overrideWithValue(homeWidget),
        if (backupFiles != null)
          backupFileStoreProvider.overrideWithValue(backupFiles),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final harness = AppHarness._(tester, container, scheduler, homeWidget);

    await harness.real(() async {
      if (settings != null) {
        await container.read(settingsRepositoryProvider).save(settings, now);
      }
      final repository = container.read(taskRepositoryProvider);
      for (final task in tasks) {
        await repository.upsert(task, task.createdAt);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TasksOrderApp(),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  /// Runs a database call of the test itself outside the fake clock of the
  /// widget test, where it would never complete.
  Future<T> real<T>(Future<T> Function() body) async =>
      await tester.runAsync(body) as T;

  /// The stored task, also when it is done or in the Trash.
  Future<Task> task(String id) async => (await real<Task?>(
    () => container.read(taskRepositoryProvider).getById(id),
  ))!;
}

/// A task created at [minute] minutes past 09:00 of the harness day, so the
/// order of equal priorities is the order of the minutes.
Task testTask(
  String id, {
  int priority = PriorityLabels.normal,
  int minute = 0,
  LocalDate? dueDate,
  LocalDate? pinnedDate,
  bool isFocused = false,
}) => Task.create(
  id: id,
  title: 'Task $id',
  priority: priority,
  dueDate: dueDate,
  isFocused: isFocused,
  now: DateTime(2026, 11, 13, 9, minute),
).copyWith(pinnedDate: pinnedDate);

/// Notifications that only remember what they were asked to do.
class FakeNotificationScheduler implements NotificationScheduler {
  FakeNotificationScheduler({this.grant = true});

  /// The answer of the user to the permission question.
  bool grant;

  int permissionRequests = 0;

  /// What is pending now, and the channel name it came with.
  List<ScheduledNotification> pending = const [];
  String? channelName;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replacePending(
    List<ScheduledNotification> notifications, {
    required String channelName,
  }) async {
    pending = notifications;
    this.channelName = channelName;
  }
}

/// A home-screen widget that only remembers what it was sent.
class FakeHomeScreenWidget implements HomeScreenWidget {
  final payloads = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<void> update(String payload) async => payloads.add(payload);
}
