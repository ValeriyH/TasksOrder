import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/data/repository/prefs_device_settings_repository.dart';
import 'package:tasks_order/domain/model/device_settings.dart';

void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer.test(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  }

  test('a fresh install follows the device', () async {
    final container = await containerWith({});

    expect(container.read(deviceSettingsProvider), const DeviceSettings());
    expect(container.read(localeProvider), isNull);
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('stored settings are there on the first read', () async {
    final container = await containerWith({
      PrefsDeviceSettingsRepository.localeKey: 'uk',
      PrefsDeviceSettingsRepository.themeModeKey: 'dark',
      PrefsDeviceSettingsRepository.showReasonsKey: false,
    });

    expect(container.read(localeProvider), const Locale('uk'));
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(deviceSettingsProvider).showReasons, isFalse);
  });

  test('a change shows at once and is stored', () async {
    final container = await containerWith({});
    final locales = <Locale?>[];
    final themes = <ThemeMode>[];
    container.listen(localeProvider, (_, next) => locales.add(next));
    container.listen(themeModeProvider, (_, next) => themes.add(next));
    final notifier = container.read(deviceSettingsProvider.notifier);

    final saving = notifier.setLocale(AppLocale.en);
    expect(container.read(localeProvider), const Locale('en'));
    await saving;
    await notifier.setThemeMode(AppThemeMode.light);
    await notifier.setShowReasons(false);
    await notifier.setLocale(AppLocale.system);
    // Listeners are told on the next flush of the container.
    await container.pump();

    expect(locales, [const Locale('en'), null]);
    expect(themes, [ThemeMode.light]);
    expect(
      container.read(deviceSettingsRepositoryProvider).load(),
      const DeviceSettings(themeMode: AppThemeMode.light, showReasons: false),
    );
  });

  test('without the override the provider says what is missing', () {
    final container = ProviderContainer.test();

    expect(() => container.read(sharedPreferencesProvider), throwsA(anything));
  });
}
