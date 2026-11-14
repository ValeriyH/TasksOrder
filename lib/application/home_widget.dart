import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/home_widget/channel_home_screen_widget.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/domain/repository/home_screen_widget.dart';
import 'package:tasks_order/domain/widget/widget_days.dart';
import 'package:tasks_order/l10n/generated/app_localizations.dart';

part 'home_widget.g.dart';

/// The home-screen widget of the device. Tests override it with a fake.
@Riverpod(keepAlive: true)
HomeScreenWidget homeScreenWidget(Ref ref) => ChannelHomeScreenWidget();

/// Lines the widget shows at most; more tasks end in "+N more".
const homeWidgetMaxLines = 8;

/// Version of the cache format, see docs/03 Data Model.md.
const homeWidgetFormat = 1;

/// The cache the home-screen widget draws from (T-601, ADR-22), as the JSON
/// text that goes to the Android side; null while the plan is loading.
///
/// Derived from the plan (D2); `TasksOrderApp` hands every new value to the
/// [HomeScreenWidget]. A string compares by value, so an unchanged plan does
/// not redraw the widget.
@Riverpod(keepAlive: true)
String? homeWidgetPayload(Ref ref) {
  final l10n = ref.watch(appLocalizationsProvider);
  final plan = ref.watch(planProvider).value;
  final tasks = ref.watch(allTasksProvider).value;
  final settings = ref.watch(settingsProvider).value;
  if (plan == null || tasks == null || settings == null) return null;

  final days = widgetDays(
    plan: plan,
    tasksById: {for (final task in tasks) task.id: task},
    doneToday: Planner.countCompletedToday(
      tasks,
      today: plan.today,
      dayStartHour: settings.dayStartHour,
    ),
  );
  return jsonEncode({
    'format': homeWidgetFormat,
    'dayStartHour': settings.dayStartHour,
    'stale': l10n.widgetStale,
    'days': [for (final day in days) _day(day, l10n)],
  });
}

Map<String, Object?> _day(WidgetDay day, AppLocalizations l10n) {
  final titles = day.titles;
  final total = titles.length + day.doneCount;
  final shown = titles.length > homeWidgetMaxLines
      ? [
          ...titles.take(homeWidgetMaxLines - 1),
          l10n.focusMore(titles.length - homeWidgetMaxLines + 1),
        ]
      : titles;
  return {
    'date': day.date.toString(),
    'header': total == 0
        ? l10n.tabToday
        : l10n.widgetHeader(titles.length, total),
    'lines': shown,
    'empty': titles.isNotEmpty
        ? null
        : day.doneCount > 0
        ? l10n.todayAllDone
        : day.isRestDay
        ? l10n.capacityRestDay
        : l10n.todayEmpty,
  };
}

/// Hands [payload] to the widget; a failure of the platform does not break
/// the app and is retried with the next change of the plan.
Future<void> applyHomeWidgetPayload(
  HomeScreenWidget widget,
  String payload,
) async {
  try {
    await widget.update(payload);
  } on Exception {
    // Nothing to do: the widget keeps the previous cache.
  }
}
