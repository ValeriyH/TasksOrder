import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';

/// The light or the dark look of the app (D13, D22).
///
/// The Material scheme is seeded from the accent and then tuned from
/// [AppColors], so the screens the redesign does not draw (editor, Settings,
/// Trash, sheets, dialogs) take the same palette without their own code
/// (ADR-23).
ThemeData appTheme(Brightness brightness) {
  final c = AppColors.forBrightness(brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.light.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        primaryContainer: c.fabBg,
        onPrimaryContainer: c.fabFg,
        secondaryContainer: c.navIndicator,
        onSecondaryContainer: c.navActive,
        error: c.alert,
        surface: c.background,
        onSurface: c.title,
        onSurfaceVariant: c.muted,
        surfaceContainerLowest: c.card,
        surfaceContainerLow: c.card,
        outline: c.filterOffBorder,
        outlineVariant: c.track,
      );

  TextStyle label(Color color, FontWeight weight) =>
      TextStyle(fontSize: 12, fontWeight: weight, color: color);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: AppDims.navBarHeight,
      backgroundColor: c.navBg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.navIndicator,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? label(c.navActive, FontWeight.w700)
            : label(c.navIdle, FontWeight.w500),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? c.navActive
              : c.navIdle,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.fabBg,
      foregroundColor: c.fabFg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDims.fabRadius),
      ),
    ),
  );
}
