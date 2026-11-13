import 'package:material_ui/material_ui.dart';

/// The colour the Material 3 schemes are derived from.
const _seedColor = Color(0xFF3F51B5);

/// The light or the dark look of the app (D13).
ThemeData appTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  ),
);
