import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/domain/model/device_settings.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/number_stepper.dart';

/// Device settings (language, theme) and planning settings. Every change is
/// stored at once and the plan follows it.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Planning horizons on offer, in days.
  static const horizons = [7, 14, 30, 60, 90, 180, 365];

  /// Upper bounds of the steppers; the domain itself has none.
  static const maxCapacity = 20;
  static const maxFocusLimit = 10;
  static const maxUrgencyDays = 60;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Header(l10n.settingsAppearance),
          const _DeviceSection(),
          _Header(l10n.settingsPlanning),
          switch (settings) {
            AsyncValue(:final value?) => _PlanningSection(settings: value),
            AsyncValue(hasError: true) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.errorLoading),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

class _DeviceSection extends ConsumerWidget {
  const _DeviceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final device = ref.watch(deviceSettingsProvider);
    final notifier = ref.read(deviceSettingsProvider.notifier);

    return Column(
      children: [
        _ChoiceTile<AppLocale>(
          name: 'language',
          icon: Icons.language,
          title: l10n.settingsLanguage,
          value: device.locale,
          options: {
            AppLocale.system: l10n.languageSystem,
            AppLocale.uk: l10n.languageUk,
            AppLocale.en: l10n.languageEn,
          },
          onChanged: (value) => unawaited(notifier.setLocale(value)),
        ),
        _ChoiceTile<AppThemeMode>(
          name: 'theme',
          icon: Icons.brightness_6_outlined,
          title: l10n.settingsTheme,
          value: device.themeMode,
          options: {
            AppThemeMode.system: l10n.themeSystem,
            AppThemeMode.light: l10n.themeLight,
            AppThemeMode.dark: l10n.themeDark,
          },
          onChanged: (value) => unawaited(notifier.setThemeMode(value)),
        ),
        SwitchListTile(
          key: const ValueKey('showReasons'),
          secondary: const Icon(Icons.label_outline),
          title: Text(l10n.settingsShowReasons),
          subtitle: Text(l10n.settingsShowReasonsHint),
          value: device.showReasons,
          onChanged: (value) => unawaited(notifier.setShowReasons(value)),
        ),
      ],
    );
  }
}

class _PlanningSection extends ConsumerWidget {
  const _PlanningSection({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final times = MaterialLocalizations.of(context);

    void save(Settings next) => unawaited(
      ref
          .read(settingsRepositoryProvider)
          .save(next, ref.read(clockProvider)()),
    );

    final weekdays = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
    final overflow = settings.maxOverflowPerDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.format_list_numbered),
          title: Text(l10n.settingsPriorityScale),
          trailing: SegmentedButton<int>(
            key: const ValueKey('scale'),
            showSelectedIcon: false,
            segments: [
              for (final scale in PriorityLabels.scales)
                ButtonSegment(
                  value: scale,
                  label: Text(l10n.plainNumber(scale)),
                ),
            ],
            selected: {settings.priorityScale},
            onSelectionChanged: (selection) => unawaited(
              _changeScale(context, ref, settings, selection.single),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            l10n.settingsWeeklyCapacity,
            style: theme.textTheme.titleSmall,
          ),
        ),
        for (var day = 0; day < 7; day++)
          ListTile(
            dense: true,
            title: Text(weekdays[day]),
            trailing: NumberStepper(
              name: 'capacity$day',
              value: settings.weeklyCapacity[day],
              min: 0,
              max: SettingsScreen.maxCapacity,
              label: settings.weeklyCapacity[day] == 0
                  ? l10n.capacityRestDay
                  : l10n.plainNumber(settings.weeklyCapacity[day]),
              onChanged: (value) => save(
                settings.copyWith(
                  weeklyCapacity: [...settings.weeklyCapacity]..[day] = value,
                ),
              ),
            ),
          ),
        const Divider(),
        ListTile(
          title: Text(l10n.settingsOverflow),
          subtitle: Text(l10n.settingsOverflowHint),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            key: const ValueKey('overflow'),
            showSelectedIcon: false,
            // The domain also allows 0, which the app does not offer (D5).
            emptySelectionAllowed: true,
            segments: [
              for (var n = 1; n <= Settings.maxOverflowLimit; n++)
                ButtonSegment(value: n, label: Text(l10n.overflowValue(n))),
            ],
            selected: {if (overflow >= 1) overflow},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                save(settings.copyWith(maxOverflowPerDay: selection.single));
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        _ChoiceTile<int>(
          name: 'horizon',
          title: l10n.settingsHorizon,
          value: settings.planningHorizonDays,
          options: {
            for (final days in {
              ...SettingsScreen.horizons,
              settings.planningHorizonDays,
            }.toList()..sort())
              days: l10n.daysCount(days),
          },
          onChanged: (value) =>
              save(settings.copyWith(planningHorizonDays: value)),
        ),
        ListTile(
          title: Text(l10n.settingsFocusLimit),
          trailing: NumberStepper(
            name: 'focusLimit',
            value: settings.focusVisibleLimit,
            min: 1,
            max: SettingsScreen.maxFocusLimit,
            label: l10n.plainNumber(settings.focusVisibleLimit),
            onChanged: (value) =>
                save(settings.copyWith(focusVisibleLimit: value)),
          ),
        ),
        _ChoiceTile<int>(
          name: 'dayStart',
          title: l10n.settingsDayStart,
          subtitle: l10n.settingsDayStartHint,
          value: settings.dayStartHour,
          options: {
            for (var hour = 0; hour < 24; hour++)
              hour: times.formatTimeOfDay(
                TimeOfDay(hour: hour, minute: 0),
                alwaysUse24HourFormat: true,
              ),
          },
          onChanged: (value) => save(settings.copyWith(dayStartHour: value)),
        ),
        ExpansionTile(
          key: const ValueKey('advanced'),
          title: Text(l10n.settingsAdvanced),
          children: [
            ListTile(
              title: Text(l10n.settingsUrgencySoon),
              trailing: NumberStepper(
                name: 'urgencySoon',
                value: settings.urgencySoonDays,
                // Never below the nearer threshold.
                min: settings.urgencyNearDays,
                max: SettingsScreen.maxUrgencyDays,
                label: l10n.daysCount(settings.urgencySoonDays),
                onChanged: (value) =>
                    save(settings.copyWith(urgencySoonDays: value)),
              ),
            ),
            ListTile(
              title: Text(l10n.settingsUrgencyNear),
              trailing: NumberStepper(
                name: 'urgencyNear',
                value: settings.urgencyNearDays,
                min: 0,
                max: settings.urgencySoonDays,
                label: l10n.daysCount(settings.urgencyNearDays),
                onChanged: (value) =>
                    save(settings.copyWith(urgencyNearDays: value)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Stores a new priority scale. A smaller one first squeezes the priorities
/// of the tasks into it, after the user agreed (T-406); a bigger one keeps
/// them (D1).
Future<void> _changeScale(
  BuildContext context,
  WidgetRef ref,
  Settings settings,
  int scale,
) async {
  final from = settings.priorityScale;
  if (scale == from) return;
  final repository = ref.read(settingsRepositoryProvider);
  final clock = ref.read(clockProvider);
  final actions = ref.read(taskActionsProvider);

  if (scale < from) {
    final tasks = ref.read(allTasksProvider).value ?? const [];
    final affected = tasks
        .where(
          (task) =>
              PriorityLabels.remap(task.priority, from: from, to: scale) !=
              task.priority,
        )
        .length;
    if (affected > 0) {
      final l10n = context.l10n;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.scaleShrinkTitle),
          content: Text(l10n.scaleShrinkBody(affected, scale)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.actionChange),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    // Also without a question: tasks in the Trash are not counted above.
    await actions.remapPriorities(from: from, to: scale);
  }
  await repository.save(settings.copyWith(priorityScale: scale), clock());
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// A row with a drop-down list of [options] (value → text). The drop-down
/// has the key `ValueKey(name)`.
class _ChoiceTile<T extends Object> extends StatelessWidget {
  const _ChoiceTile({
    required this.name,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String name;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon == null ? null : Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: DropdownButton<T>(
        key: ValueKey(name),
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final MapEntry(key: option, value: text) in options.entries)
            DropdownMenuItem(value: option, child: Text(text)),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
