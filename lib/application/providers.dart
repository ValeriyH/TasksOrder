import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/data/repository/drift_day_override_repository.dart';
import 'package:tasks_order/data/repository/drift_settings_repository.dart';
import 'package:tasks_order/data/repository/drift_task_repository.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/domain/repository/day_override_repository.dart';
import 'package:tasks_order/domain/repository/settings_repository.dart';
import 'package:tasks_order/domain/repository/task_repository.dart';

part 'providers.g.dart';

/// Gives the current instant. Tests override [clockProvider] with a fixed one.
typedef Clock = DateTime Function();

/// The clock every `now` passed to a repository comes from.
@Riverpod(keepAlive: true)
Clock clock(Ref ref) => DateTime.now;

/// The local store. Tests override it with an in-memory database.
@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
TaskRepository taskRepository(Ref ref) =>
    DriftTaskRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    DriftSettingsRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
DayOverrideRepository dayOverrideRepository(Ref ref) =>
    DriftDayOverrideRepository(ref.watch(databaseProvider));

/// Active and done tasks, without the Trash.
///
/// The plan needs both kinds: the active ones to place and the done ones to
/// count today's completions. Taking them from one stream means a completion
/// arrives as one change, so the plan never sees the task gone while the
/// count is still the old one.
@Riverpod(keepAlive: true)
Stream<List<Task>> allTasks(Ref ref) =>
    ref.watch(taskRepositoryProvider).watchAll();

/// Deleted tasks, the most recently deleted first (D14).
@riverpod
Stream<List<Task>> trash(Ref ref) =>
    ref.watch(taskRepositoryProvider).watchTrash();

/// Tasks still to do, oldest first.
@Riverpod(keepAlive: true)
AsyncValue<List<Task>> activeTasks(Ref ref) => ref
    .watch(allTasksProvider)
    .whenData((tasks) => [...tasks.where((task) => !task.isDone)]);

/// The planning settings.
@Riverpod(keepAlive: true)
Stream<Settings> settings(Ref ref) =>
    ref.watch(settingsRepositoryProvider).watch();

/// Capacity overrides keyed by date.
@Riverpod(keepAlive: true)
Stream<Map<LocalDate, DayOverride>> dayOverrides(Ref ref) =>
    ref.watch(dayOverrideRepositoryProvider).watchAll();

/// The calendar day the user is in: it starts at `Settings.dayStartHour`
/// (D15).
///
/// A timer recomputes it at the next day start, so the plan rolls over while
/// the app is open; a change of `dayStartHour` recomputes it and re-arms the
/// timer. Listeners are notified only when the date really changes.
@Riverpod(keepAlive: true)
AsyncValue<LocalDate> today(Ref ref) {
  final dayStartHour = ref.watch(
    settingsProvider.select(
      (settings) => settings.whenData((value) => value.dayStartHour),
    ),
  );
  final now = ref.watch(clockProvider)().toLocal();

  final hour = dayStartHour.value;
  if (hour != null) {
    // A timer that fires a little early finds the same date and arms a short
    // one for the rest; a late one (the device slept) finds the new date.
    final timer = Timer(
      _nextDayStart(now, hour).difference(now),
      ref.invalidateSelf,
    );
    ref.onDispose(timer.cancel);
  }
  return dayStartHour.whenData((hour) => LocalDate.todayFor(now, hour));
}

/// The first moment after [now] (local time) when the clock shows
/// [dayStartHour]:00.
DateTime _nextDayStart(DateTime now, int dayStartHour) {
  final sameDay = DateTime(now.year, now.month, now.day, dayStartHour);
  if (sameDay.isAfter(now)) return sameDay;
  // Built from calendar fields, not by adding 24 hours: a DST switch must not
  // move the boundary.
  return DateTime(now.year, now.month, now.day + 1, dayStartHour);
}

/// The plan (ADR-1: derived, never stored). Recomputed when tasks, settings,
/// overrides or the day change; loading until all four have arrived.
@Riverpod(keepAlive: true)
AsyncValue<Plan> plan(Ref ref) {
  final tasks = ref.watch(allTasksProvider);
  final settings = ref.watch(settingsProvider);
  final overrides = ref.watch(dayOverridesProvider);
  final today = ref.watch(todayProvider);

  // An input that failed after it had a value keeps that value.
  for (final AsyncValue<Object> input in [tasks, settings, overrides, today]) {
    if (input.hasError && !input.hasValue) {
      return AsyncError(input.error!, input.stackTrace!);
    }
  }
  final allTasks = tasks.value;
  final currentSettings = settings.value;
  final currentOverrides = overrides.value;
  final currentDay = today.value;
  if (allTasks == null ||
      currentSettings == null ||
      currentOverrides == null ||
      currentDay == null) {
    return const AsyncLoading();
  }

  return AsyncData(
    const Planner().plan(
      activeTasks: [...allTasks.where((task) => !task.isDone)],
      settings: currentSettings,
      overrides: currentOverrides,
      today: currentDay,
      // Completions from today's list leave their slot empty (D3, D19).
      completedTodayCount: Planner.countCompletedToday(
        allTasks,
        today: currentDay,
        dayStartHour: currentSettings.dayStartHour,
      ),
    ),
  );
}
