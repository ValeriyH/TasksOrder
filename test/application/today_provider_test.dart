import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';

void main() {
  final friday = LocalDate(2026, 11, 13);
  final saturday = LocalDate(2026, 11, 14);
  final sunday = LocalDate(2026, 11, 15);

  /// Runs [body] under a fake clock that starts at [start] (local time) and
  /// moves with the fake timers. The settings come from the returned sink.
  void runAt(
    DateTime start,
    void Function(
      FakeAsync async,
      ProviderContainer container,
      StreamController<Settings> settings,
    )
    body, {
    List<Task> tasks = const [],
  }) {
    fakeAsync((async) {
      final settings = StreamController<Settings>();
      final container = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => start.add(async.elapsed)),
          settingsProvider.overrideWith((ref) => settings.stream),
          allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
          dayOverridesProvider.overrideWith(
            (ref) => Stream.value(const <LocalDate, DayOverride>{}),
          ),
        ],
      );
      body(async, container, settings);
      container.dispose();
      expect(async.pendingTimers, isEmpty, reason: 'timer left after dispose');
      unawaited(settings.close());
    });
  }

  /// Subscribes to `todayProvider` and collects every date it reports.
  List<LocalDate> listen(ProviderContainer container) {
    final seen = <LocalDate>[];
    container.listen(todayProvider, (_, next) {
      if (next.value case final date?) seen.add(date);
    }, fireImmediately: true);
    return seen;
  }

  test('loading until the settings arrive, and no timer before that', () {
    runAt(DateTime(2026, 11, 13, 10), (async, container, settings) {
      final seen = listen(container);
      async.elapse(Duration.zero);

      expect(container.read(todayProvider).isLoading, isTrue);
      expect(seen, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('the day changes at midnight by default', () {
    runAt(DateTime(2026, 11, 13, 23, 59), (async, container, settings) {
      final seen = listen(container);
      settings.add(Settings());
      async.elapse(Duration.zero);
      expect(seen, [friday]);

      async.elapse(const Duration(seconds: 59));
      expect(seen, [friday]);

      async.elapse(const Duration(seconds: 1));
      expect(seen, [friday, saturday]);
      expect(container.read(todayProvider).requireValue, saturday);
    });
  });

  test('with dayStartHour 4 the day changes at 04:00, not at midnight', () {
    runAt(DateTime(2026, 11, 13, 23, 59), (async, container, settings) {
      final seen = listen(container);
      settings.add(Settings(dayStartHour: 4));
      async.elapse(Duration.zero);

      // 03:59 on Saturday by the calendar.
      async.elapse(const Duration(hours: 4));
      expect(seen, [friday]);

      async.elapse(const Duration(minutes: 1));
      expect(seen, [friday, saturday]);
    });
  });

  test('the timer is re-armed for every following day', () {
    runAt(DateTime(2026, 11, 13, 10), (async, container, settings) {
      final seen = listen(container);
      settings.add(Settings(dayStartHour: 4));
      async.elapse(Duration.zero);

      async.elapse(const Duration(hours: 18));
      expect(seen, [friday, saturday]);

      async.elapse(const Duration(hours: 24));
      expect(seen, [friday, saturday, sunday]);
      expect(async.pendingTimers, hasLength(1));
    });
  });

  test('a new dayStartHour takes effect at once and moves the timer', () {
    // 02:00 on Saturday.
    runAt(DateTime(2026, 11, 14, 2), (async, container, settings) {
      final seen = listen(container);
      settings.add(Settings());
      async.elapse(Duration.zero);
      expect(seen, [saturday]);

      // The day now starts at 04:00, so it is Friday again.
      settings.add(Settings(dayStartHour: 4));
      async.elapse(Duration.zero);
      expect(seen, [saturday, friday]);
      expect(async.pendingTimers, hasLength(1));

      async.elapse(const Duration(hours: 2));
      expect(seen, [saturday, friday, saturday]);

      // The old midnight timer is gone: nothing happens at the next midnight.
      async.elapse(const Duration(hours: 20));
      expect(seen, [saturday, friday, saturday]);
    });
  });

  test('other settings changes neither notify nor re-arm', () {
    runAt(DateTime(2026, 11, 13, 10), (async, container, settings) {
      final seen = listen(container);
      settings.add(Settings());
      async.elapse(Duration.zero);
      final timer = async.pendingTimers.single;

      settings.add(Settings(planningHorizonDays: 30));
      async.elapse(Duration.zero);

      expect(seen, [friday]);
      expect(async.pendingTimers.single, same(timer));
    });
  });

  test('the plan rolls over to the new day', () {
    final task = Task.create(
      id: 'a',
      title: 'Task a',
      priority: 1,
      now: DateTime(2026, 11, 13, 9),
    );

    runAt(DateTime(2026, 11, 13, 23, 30), tasks: [task], (
      async,
      container,
      settings,
    ) {
      container.listen(planProvider, (_, _) {});
      settings.add(Settings());
      async.elapse(Duration.zero);

      var plan = container.read(planProvider).requireValue;
      expect(plan.today, friday);
      expect(plan.days.first.date, friday);
      expect(plan.days.first.entries.single.taskId, 'a');

      async.elapse(const Duration(minutes: 30));

      // Not done on Friday, so it is planned for Saturday.
      plan = container.read(planProvider).requireValue;
      expect(plan.today, saturday);
      expect(plan.days.first.date, saturday);
      expect(plan.days.first.entries.single.taskId, 'a');
    });
  });
}
