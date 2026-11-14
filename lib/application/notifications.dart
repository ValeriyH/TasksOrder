import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/notifications/local_notification_scheduler.dart';
import 'package:tasks_order/domain/notification/morning_digest.dart';
import 'package:tasks_order/domain/repository/notification_scheduler.dart';

part 'notifications.g.dart';

/// The notifications of the device. Tests override it with a fake.
@Riverpod(keepAlive: true)
NotificationScheduler notificationScheduler(Ref ref) =>
    LocalNotificationScheduler();

/// What the morning notification should look like for the next week
/// (T-501): empty when it is off, null while the plan is loading.
///
/// Derived from the plan like everything else (D2); `TasksOrderApp` hands
/// every new value to the [NotificationScheduler].
@Riverpod(keepAlive: true)
MorningSchedule? morningSchedule(Ref ref) {
  final time = ref.watch(
    deviceSettingsProvider.select((settings) => settings.notificationTime),
  );
  final l10n = ref.watch(appLocalizationsProvider);
  if (time == null) {
    return MorningSchedule(const [], channelName: l10n.notificationChannel);
  }

  final plan = ref.watch(planProvider).value;
  final tasks = ref.watch(allTasksProvider).value;
  final settings = ref.watch(settingsProvider).value;
  if (plan == null || tasks == null || settings == null) return null;

  final digests = morningDigests(
    plan: plan,
    tasksById: {for (final task in tasks) task.id: task},
    minuteOfDay: time,
    dayStartHour: settings.dayStartHour,
    now: ref.read(clockProvider)().toLocal(),
  );
  return MorningSchedule([
    for (final digest in digests)
      ScheduledNotification(
        id: digest.id,
        at: digest.at,
        title: l10n.notificationTitle(digest.titles.length),
        lines: digest.titles,
      ),
  ], channelName: l10n.notificationChannel);
}

/// The notifications to have pending, with the channel name in the app's
/// language.
final class MorningSchedule {
  const MorningSchedule(this.notifications, {required this.channelName});

  final List<ScheduledNotification> notifications;
  final String channelName;

  @override
  bool operator ==(Object other) =>
      other is MorningSchedule &&
      other.channelName == channelName &&
      other.notifications.length == notifications.length &&
      Iterable<int>.generate(notifications.length)
          .every((i) => other.notifications[i] == notifications[i]);

  @override
  int get hashCode => Object.hash(channelName, Object.hashAll(notifications));
}

/// Hands [schedule] to the scheduler; a failure of the platform is not the
/// user's problem and does not break the app.
Future<void> applyMorningSchedule(
  NotificationScheduler scheduler,
  MorningSchedule schedule,
) async {
  try {
    await scheduler.replacePending(
      schedule.notifications,
      channelName: schedule.channelName,
    );
  } on Exception {
    // Tried again on the next change of the plan.
  }
}
