import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/features/settings/settings_screen.dart';
import 'package:tasks_order/shared/task_tile.dart';

import 'app_harness.dart';

void main() {
  /// Starts the app on a screen tall enough for the whole list and opens the
  /// Settings tab.
  Future<AppHarness> start(
    WidgetTester tester, {
    List<Task> tasks = const [],
    Settings? settings,
    Map<String, Object> stored = const {},
  }) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      settings: settings,
      stored: stored,
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    return app;
  }

  Settings current(AppHarness app) =>
      app.container.read(settingsProvider).requireValue;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  /// The text a stepper shows for its value.
  String shown(WidgetTester tester, String name) =>
      tester.widget<Text>(find.byKey(ValueKey('$name='))).data!;

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed != null;

  /// Opens the drop-down [name] and picks the option with this text.
  Future<void> choose(WidgetTester tester, String name, String option) async {
    await tapKey(tester, name);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> segment(WidgetTester tester, String name, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey(name)),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the stored settings', (tester) async {
    await start(tester);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Device language'), findsOneWidget);
    expect(find.text('As on the device'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byKey(const ValueKey('scale')))
          .selected,
      {5},
    );
    expect(shown(tester, 'capacity0'), '1');
    expect(shown(tester, 'capacity5'), '3');
    expect(shown(tester, 'capacity6'), 'Rest day');
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byKey(const ValueKey('overflow')))
          .selected,
      {1},
    );
    expect(find.text('90 days'), findsOneWidget);
    expect(shown(tester, 'focusLimit'), '3');
    expect(find.text('00:00'), findsOneWidget);
  });

  group('planning settings are stored at once', () {
    testWidgets('priority scale', (tester) async {
      final app = await start(tester);

      await segment(tester, 'scale', '10');

      expect(current(app).priorityScale, 10);
    });

    testWidgets('capacity of a weekday, down to a rest day', (tester) async {
      final app = await start(tester);

      await tapKey(tester, 'capacity4+');
      expect(current(app).weeklyCapacity, [1, 1, 1, 1, 2, 3, 0]);
      expect(shown(tester, 'capacity4'), '2');

      await tapKey(tester, 'capacity0-');
      expect(current(app).weeklyCapacity, [0, 1, 1, 1, 2, 3, 0]);
      expect(shown(tester, 'capacity0'), 'Rest day');
      expect(enabled(tester, 'capacity0-'), isFalse);
    });

    testWidgets('overflow', (tester) async {
      final app = await start(tester);

      await segment(tester, 'overflow', '+3');

      expect(current(app).maxOverflowPerDay, 3);
    });

    testWidgets('horizon, Focus limit and day start', (tester) async {
      final app = await start(tester);

      await choose(tester, 'horizon', '30 days');
      await tapKey(tester, 'focusLimit+');
      await choose(tester, 'dayStart', '04:00');

      expect(current(app).planningHorizonDays, 30);
      expect(current(app).focusVisibleLimit, 4);
      expect(current(app).dayStartHour, 4);
    });

    testWidgets('a horizon that is not on the list stays selectable', (
      tester,
    ) async {
      await start(tester, settings: Settings(planningHorizonDays: 45));

      expect(find.text('45 days'), findsOneWidget);
    });

    testWidgets('urgency thresholds keep near <= soon', (tester) async {
      final app = await start(
        tester,
        settings: Settings(urgencySoonDays: 3, urgencyNearDays: 2),
      );
      await tapKey(tester, 'advanced');

      await tapKey(tester, 'urgencyNear+');
      expect(current(app).urgencyNearDays, 3);
      expect(shown(tester, 'urgencyNear'), '3 days');
      // Near has reached soon: neither can cross the other.
      expect(enabled(tester, 'urgencyNear+'), isFalse);
      expect(enabled(tester, 'urgencySoon-'), isFalse);

      await tapKey(tester, 'urgencySoon+');
      expect(current(app).urgencySoonDays, 4);
      expect(enabled(tester, 'urgencyNear+'), isTrue);
    });
  });

  group('the priority scale (ADR-17)', () {
    final tasks = [
      testTask('catastrophic', priority: 1),
      testTask('normal', minute: 1),
      testTask('someday', priority: 8, minute: 2),
    ];

    for (final scale in ['3', '10']) {
      testWidgets('to $scale: no question, the tasks keep their levels', (
        tester,
      ) async {
        final app = await start(tester, tasks: tasks);

        await segment(tester, 'scale', scale);

        expect(find.byType(AlertDialog), findsNothing);
        expect(current(app).priorityScale, int.parse(scale));
        expect((await app.task('catastrophic')).priority, 1);
        expect((await app.task('normal')).priority, 5);
        expect((await app.task('someday')).priority, 8);
      });
    }

    testWidgets('a round trip 5 -> 10 -> 3 -> 5 changes nothing', (
      tester,
    ) async {
      final app = await start(tester, tasks: tasks);

      for (final scale in ['10', '3', '5']) {
        await segment(tester, 'scale', scale);
      }

      expect(current(app).priorityScale, 5);
      expect(
        [
          for (final id in ['catastrophic', 'normal', 'someday'])
            (await app.task(id)).priority,
        ],
        [1, 5, 8],
      );
    });
  });

  testWidgets('a capacity change recomputes the plan', (tester) async {
    await start(
      tester,
      tasks: [testTask('a', priority: 1), testTask('b', priority: 2)],
    );

    // Friday: from one task a day to two.
    await tapKey(tester, 'capacity4+');
    await tester.tap(find.byIcon(Icons.today_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(TaskTile), findsNWidgets(2));
    expect(find.text('Planned 2/2'), findsOneWidget);
  });

  group('device settings', () {
    testWidgets('the language switches at once and is stored', (tester) async {
      await start(tester);

      await choose(tester, 'language', 'Українська');

      expect(find.text('Вигляд'), findsOneWidget);
      expect(find.text('Понеділок'), findsOneWidget);
      expect(find.text('Вихідний'), findsOneWidget);
      expect(find.text('90 днів'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('device.locale'), 'uk');

      await choose(tester, 'language', 'English');
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('the theme switches at once and is stored', (tester) async {
      await start(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(SettingsScreen))).brightness;
      expect(brightness(), Brightness.light);

      await choose(tester, 'theme', 'Dark');

      expect(brightness(), Brightness.dark);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('device.themeMode'), 'dark');
    });

    testWidgets('the reason badges can be switched off', (tester) async {
      await start(tester);

      await tapKey(tester, 'showReasons');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('device.showReasons'), isFalse);
    });
  });
}
