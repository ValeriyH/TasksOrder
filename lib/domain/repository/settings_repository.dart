import 'package:tasks_order/domain/model/settings.dart';

/// Storage of the planning settings (a single record).
abstract interface class SettingsRepository {
  /// The current settings, then every change. Gives the defaults when
  /// nothing is stored.
  Stream<Settings> watch();

  /// Stores [settings]; [now] becomes the time of the change.
  Future<void> save(Settings settings, DateTime now);
}
