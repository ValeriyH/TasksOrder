import 'package:tasks_order/domain/model/device_settings.dart';

/// Storage of the settings that belong to this device and never sync (D12).
abstract interface class DeviceSettingsRepository {
  /// The stored settings; defaults for anything missing or unreadable.
  DeviceSettings load();

  Future<void> save(DeviceSettings settings);
}
