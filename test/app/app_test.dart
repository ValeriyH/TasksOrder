import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/app/app.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/device_settings.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/features/plan/plan_screen.dart';
import 'package:tasks_order/features/settings/settings_screen.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/tasks/tasks_screen.dart';
import 'package:tasks_order/features/today/today_screen.dart';

import '../data/test_database.dart';

void main() {
  /// Starts the app with the given stored device settings and returns the
  /// container behind it.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    DateTime Function()? clock,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        databaseProvider.overrideWithValue(db),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TasksOrderApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// The language of the device, as the framework reads it.
  void setDeviceLocale(WidgetTester tester, Locale locale) {
    tester.platformDispatcher.localeTestValue = locale;
    tester.platformDispatcher.localesTestValue = [locale];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  }

  /// The labels of the bottom navigation, left to right.
  List<String> tabLabels(WidgetTester tester) => [
    for (final destination in tester.widgetList<NavigationDestination>(
      find.byType(NavigationDestination),
    ))
      destination.label,
  ];

  Brightness brightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(TodayScreen))).brightness;

  const english = ['Today', 'Plan', 'Tasks', 'Settings'];
  const ukrainian = ['Сьогодні', 'План', 'Завдання', 'Налаштування'];

  group('navigation', () {
    testWidgets('starts on Today with four tabs', (tester) async {
      await pumpApp(tester);

      expect(find.byType(TodayScreen), findsOneWidget);
      expect(tabLabels(tester), english);
    });

    testWidgets('a tap on a tab opens its screen', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksScreen), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('the editor opens above the tabs and back returns to them', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      final router = container.read(routerProvider);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      unawaited(router.push(AppRoutes.taskNew));
      await tester.pumpAndSettle();
      var editor = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(editor.taskId, isNull);
      expect(find.text('New task'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TasksScreen), findsOneWidget);

      unawaited(router.push(AppRoutes.task('abc-1')));
      await tester.pumpAndSettle();
      editor = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(editor.taskId, 'abc-1');
      expect(find.text('Edit task'), findsOneWidget);
    });
  });

  group('language (D13)', () {
    testWidgets('follows the device by default', (tester) async {
      setDeviceLocale(tester, const Locale('uk', 'UA'));
      await pumpApp(tester);

      expect(tabLabels(tester), ukrainian);

      setDeviceLocale(tester, const Locale('en', 'GB'));
      await tester.pumpAndSettle();
      expect(tabLabels(tester), english);
    });

    testWidgets('a language the app does not have gives English', (
      tester,
    ) async {
      setDeviceLocale(tester, const Locale('de', 'DE'));
      await pumpApp(tester);

      expect(tabLabels(tester), english);
    });

    testWidgets('the stored language wins over the device', (tester) async {
      setDeviceLocale(tester, const Locale('en', 'US'));
      await pumpApp(tester, stored: {'device.locale': 'uk'});

      expect(tabLabels(tester), ukrainian);
    });

    testWidgets('a change shows at once', (tester) async {
      final container = await pumpApp(tester);
      expect(tabLabels(tester), english);

      await container
          .read(deviceSettingsProvider.notifier)
          .setLocale(AppLocale.uk);
      await tester.pumpAndSettle();

      expect(tabLabels(tester), ukrainian);
    });
  });

  group('theme (D13)', () {
    testWidgets('follows the device by default', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester);

      expect(brightness(tester), Brightness.dark);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
    });

    testWidgets('the stored theme wins and a change shows at once', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final container = await pumpApp(
        tester,
        stored: {'device.themeMode': 'dark'},
      );
      expect(brightness(tester), Brightness.dark);
      expect(
        Theme.of(tester.element(find.byType(TodayScreen))).useMaterial3,
        isTrue,
      );

      await container
          .read(deviceSettingsProvider.notifier)
          .setThemeMode(AppThemeMode.light);
      await tester.pumpAndSettle();

      expect(brightness(tester), Brightness.light);
    });
  });

  testWidgets('the day is checked again when the app is resumed', (
    tester,
  ) async {
    var now = DateTime(2026, 11, 13, 22);
    final container = await pumpApp(tester, clock: () => now);
    container.listen(todayProvider, (_, _) {});
    await tester.pump();
    expect(container.read(todayProvider).requireValue, LocalDate(2026, 11, 13));

    // The phone slept through midnight: no timer fired.
    now = DateTime(2026, 11, 14, 7);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    expect(container.read(todayProvider).requireValue, LocalDate(2026, 11, 14));
  });
}
