import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:tasks_order/domain/repository/notification_scheduler.dart';
import 'package:timezone/timezone.dart' as tz;

/// [NotificationScheduler] on `flutter_local_notifications`, Android only
/// (T-501). Elsewhere [isSupported] is false and every call does nothing.
///
/// Notifications are scheduled as single ones for a given instant, not as a
/// repeating one: every day has its own text. The instant is given in UTC,
/// which needs no time zone database; the local wall-clock time and DST were
/// already taken into account when the `DateTime` was built.
///
/// Inexact alarms: the notification may come a few minutes late, but the app
/// needs no "alarms and reminders" permission.
class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'morning';

  /// The small monochrome icon in the status bar, see
  /// `android/app/src/main/res/drawable/ic_notification.xml`.
  static const _icon = 'ic_notification';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialized;

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _initialize() => _initialized ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings(_icon),
    ),
  );

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await _initialize();
    // Null below Android 13, where no permission is needed.
    final granted = await _android?.requestNotificationsPermission();
    if (granted != null) return granted;
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<void> replacePending(
    List<ScheduledNotification> notifications, {
    required String channelName,
  }) async {
    if (!isSupported) return;
    await _initialize();
    // Only the pending ones: the notification shown this morning stays.
    await _plugin.cancelAllPendingNotifications();
    final now = DateTime.now();
    for (final notification in notifications) {
      if (!notification.at.isAfter(now)) continue;
      final lines = notification.lines;
      await _plugin.zonedSchedule(
        id: notification.id,
        scheduledDate: tz.TZDateTime.from(notification.at.toUtc(), tz.UTC),
        title: notification.title,
        body: lines.join(', '),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            channelName,
            icon: _icon,
            styleInformation: InboxStyleInformation(
              lines,
              contentTitle: notification.title,
            ),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
