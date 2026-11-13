import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/data/repository/prefs_device_settings_repository.dart';
import 'package:tasks_order/domain/model/device_settings.dart';

void main() {
  Future<PrefsDeviceSettingsRepository> repoWith(
    Map<String, Object> stored,
  ) async {
    SharedPreferences.setMockInitialValues(stored);
    return PrefsDeviceSettingsRepository(await SharedPreferences.getInstance());
  }

  test('the defaults follow the device', () {
    const defaults = DeviceSettings();
    expect(defaults.locale, AppLocale.system);
    expect(defaults.themeMode, AppThemeMode.system);
    expect(defaults.showReasons, isTrue);
  });

  test('nothing stored gives the defaults', () async {
    final repo = await repoWith({});

    expect(repo.load(), const DeviceSettings());
  });

  test('saved settings are read back', () async {
    final repo = await repoWith({});
    const settings = DeviceSettings(
      locale: AppLocale.uk,
      themeMode: AppThemeMode.dark,
      showReasons: false,
    );
    await repo.save(settings);

    expect(repo.load(), settings);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsDeviceSettingsRepository.localeKey), 'uk');
    expect(prefs.getString(PrefsDeviceSettingsRepository.themeModeKey), 'dark');
    expect(prefs.getBool(PrefsDeviceSettingsRepository.showReasonsKey), false);
  });

  test('an unknown name falls back to the default of that field', () async {
    final repo = await repoWith({
      PrefsDeviceSettingsRepository.localeKey: 'fr',
      PrefsDeviceSettingsRepository.themeModeKey: 'light',
    });

    expect(repo.load(), const DeviceSettings(themeMode: AppThemeMode.light));
  });

  test('a value of the wrong type falls back to the default', () async {
    final repo = await repoWith({
      PrefsDeviceSettingsRepository.localeKey: 42,
      PrefsDeviceSettingsRepository.showReasonsKey: 'no',
    });

    expect(repo.load(), const DeviceSettings());
  });
}
