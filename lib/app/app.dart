import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/app/theme.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/home_widget.dart';
import 'package:tasks_order/application/notifications.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/application/task_actions.dart';
import 'package:tasks_order/l10n/l10n.dart';

/// The root widget: router, languages and themes (D13).
///
/// Needs a `ProviderScope` above it with `sharedPreferencesProvider`
/// overridden, see `main`.
class TasksOrderApp extends ConsumerStatefulWidget {
  const TasksOrderApp({super.key});

  @override
  ConsumerState<TasksOrderApp> createState() => _TasksOrderAppState();
}

class _TasksOrderAppState extends ConsumerState<TasksOrderApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // The day timer does not run while the app is suspended, so the day is
    // checked again when the app comes back (T-205).
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(todayProvider),
    );
    // Tasks deleted long ago leave the Trash for good (D14).
    unawaited(ref.read(taskActionsProvider).purgeOldTrash());
    // The morning notifications follow the plan (T-501): every change of
    // the plan, the language or the time reschedules the coming week.
    ref.listenManual(morningScheduleProvider, (_, schedule) {
      if (schedule == null) return;
      unawaited(
        applyMorningSchedule(ref.read(notificationSchedulerProvider), schedule),
      );
    }, fireImmediately: true);
    // So does the home-screen widget (T-601).
    final homeWidget = ref.read(homeScreenWidgetProvider);
    if (homeWidget.isSupported) {
      ref.listenManual(homeWidgetPayloadProvider, (_, payload) {
        if (payload == null) return;
        unawaited(applyHomeWidgetPayload(homeWidget, payload));
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      routerConfig: ref.watch(routerProvider),
      // Null follows the device; a language the app does not have falls back
      // to the first supported one, English.
      locale: ref.watch(localeProvider),
      // The Material and Cupertino texts come from material_ui: the delegates
      // of flutter_localizations, which the generated AppLocalizations lists,
      // are for the Material library that used to live in the Flutter SDK.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsStyle(Theme.of(context).brightness),
        child: child!,
      ),
    );
  }
}

/// The Android system navigation bar follows the theme of the app, not the
/// one of the device (T-503): transparent, so the app's own bottom bar or
/// background shows under it, with icons that stand out against it.
SystemUiOverlayStyle systemBarsStyle(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}
