import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_settings.freezed.dart';

/// Language of the UI (D13).
enum AppLocale {
  /// The language of the device; English when it is not supported.
  system,
  uk,
  en,
}

/// Light or dark look (D13).
enum AppThemeMode {
  /// Whatever the device uses.
  system,
  light,
  dark,
}

/// Settings of this device: they stay local and never mix with the planning
/// `Settings`, which would sync per user (D12).
@freezed
abstract class DeviceSettings with _$DeviceSettings {
  const factory DeviceSettings({
    @Default(AppLocale.system) AppLocale locale,
    @Default(AppThemeMode.system) AppThemeMode themeMode,

    /// Show the "due / pinned / overflow" badges in the plan.
    @Default(true) bool showReasons,
  }) = _DeviceSettings;
}
