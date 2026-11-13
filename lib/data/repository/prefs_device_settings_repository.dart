import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/domain/model/device_settings.dart';
import 'package:tasks_order/domain/repository/device_settings_repository.dart';

/// [DeviceSettingsRepository] in SharedPreferences. Enums are stored by name.
class PrefsDeviceSettingsRepository implements DeviceSettingsRepository {
  PrefsDeviceSettingsRepository(this._prefs);

  static const localeKey = 'device.locale';
  static const themeModeKey = 'device.themeMode';
  static const showReasonsKey = 'device.showReasons';

  final SharedPreferences _prefs;

  @override
  DeviceSettings load() {
    const defaults = DeviceSettings();
    return DeviceSettings(
      locale: _enum(localeKey, AppLocale.values) ?? defaults.locale,
      themeMode: _enum(themeModeKey, AppThemeMode.values) ?? defaults.themeMode,
      showReasons:
          _read(_prefs.getBool, showReasonsKey) ?? defaults.showReasons,
    );
  }

  @override
  Future<void> save(DeviceSettings settings) async {
    await _prefs.setString(localeKey, settings.locale.name);
    await _prefs.setString(themeModeKey, settings.themeMode.name);
    await _prefs.setBool(showReasonsKey, settings.showReasons);
  }

  /// Null when the stored name is not one of [values], e.g. written by a
  /// newer version of the app.
  T? _enum<T extends Enum>(String key, List<T> values) {
    final name = _read(_prefs.getString, key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// Null also when the key holds a value of another type.
  static T? _read<T>(T? Function(String key) getter, String key) {
    try {
      return getter(key);
    } on TypeError {
      return null;
    }
  }
}
