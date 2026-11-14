/// A notification to show at a given local time.
final class ScheduledNotification {
  const ScheduledNotification({
    required this.id,
    required this.at,
    required this.title,
    required this.lines,
  });

  /// Rescheduling with the same id replaces the notification.
  final int id;

  /// Local time.
  final DateTime at;
  final String title;

  /// The body, one line per task.
  final List<String> lines;

  @override
  bool operator ==(Object other) =>
      other is ScheduledNotification &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.lines.length == lines.length &&
      Iterable<int>.generate(lines.length)
          .every((i) => other.lines[i] == lines[i]);

  @override
  int get hashCode => Object.hash(id, at, title, Object.hashAll(lines));

  @override
  String toString() => 'ScheduledNotification($id, $at, $title, $lines)';
}

/// Local notifications of the device (T-501). The platform implementation
/// lives in `lib/data`; tests use a fake.
abstract interface class NotificationScheduler {
  /// Whether this platform can show scheduled notifications at all; the
  /// setting is hidden where it cannot.
  bool get isSupported;

  /// Asks the user for the permission to notify (Android 13+). True when
  /// notifications may be shown.
  Future<bool> requestPermission();

  /// Replaces every notification that has not been shown yet with
  /// [notifications]; the ones already shown stay. [channelName] is the name
  /// of the notification channel in the system settings.
  Future<void> replacePending(
    List<ScheduledNotification> notifications, {
    required String channelName,
  });
}
