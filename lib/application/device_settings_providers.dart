import 'dart:ui' show Locale;

import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks_order/data/repository/prefs_device_settings_repository.dart';
import 'package:tasks_order/domain/model/device_settings.dart';
import 'package:tasks_order/domain/repository/device_settings_repository.dart';

part 'device_settings_providers.g.dart';

/// SharedPreferences are loaded asynchronously, so `main` awaits
/// `SharedPreferences.getInstance()` and overrides this provider with the
/// result; device settings can then be read synchronously on the first frame.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) => throw UnimplementedError(
  'Override sharedPreferencesProvider with a loaded instance',
);

@Riverpod(keepAlive: true)
DeviceSettingsRepository deviceSettingsRepository(Ref ref) =>
    PrefsDeviceSettingsRepository(ref.watch(sharedPreferencesProvider));

/// The device settings and the way to change them. A change shows at once and
/// is stored in the background.
@Riverpod(keepAlive: true)
class DeviceSettingsNotifier extends _$DeviceSettingsNotifier {
  @override
  DeviceSettings build() => ref.watch(deviceSettingsRepositoryProvider).load();

  Future<void> setLocale(AppLocale locale) =>
      _save(state.copyWith(locale: locale));

  Future<void> setThemeMode(AppThemeMode themeMode) =>
      _save(state.copyWith(themeMode: themeMode));

  Future<void> setShowReasons(bool showReasons) =>
      _save(state.copyWith(showReasons: showReasons));

  Future<void> _save(DeviceSettings settings) {
    state = settings;
    return ref.read(deviceSettingsRepositoryProvider).save(settings);
  }
}

/// Locale for `MaterialApp.locale`; null follows the device (D13).
@riverpod
Locale? locale(Ref ref) => switch (ref.watch(deviceSettingsProvider).locale) {
  AppLocale.system => null,
  AppLocale.uk => const Locale('uk'),
  AppLocale.en => const Locale('en'),
};

/// Theme mode for `MaterialApp.themeMode` (D13).
@riverpod
ThemeMode themeMode(Ref ref) =>
    switch (ref.watch(deviceSettingsProvider).themeMode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
