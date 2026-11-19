import 'package:material_ui/material_ui.dart';

/// The colours of the redesign (D22, ADR-23) for the light and the dark
/// theme, taken from the tokens of the owner's design package.
///
/// Read with `AppColors.of(context)`. The Material `ColorScheme` of
/// `appTheme` is tuned from the same values, so the screens the redesign
/// does not draw follow them too. Priority colours are not here: they stay
/// the app's own (D1), see [PriorityShade].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.cardShadow,
    required this.title,
    required this.titleDone,
    required this.muted,
    required this.strong,
    required this.accent,
    required this.onAccent,
    required this.track,
    required this.neutralChipBg,
    required this.neutralChipFg,
    required this.metaText,
    required this.metaExtra,
    required this.priorityDotDone,
    required this.notesBg,
    required this.notesText,
    required this.accentChipBg,
    required this.accentChipFg,
    required this.extraChipBg,
    required this.extraChipFg,
    required this.alert,
    required this.doneButtonBg,
    required this.doneButtonFg,
    required this.capPillBg,
    required this.capPillFg,
    required this.capOverBg,
    required this.capOverFg,
    required this.dotOff,
    required this.freeBorder,
    required this.todayName,
    required this.filterOnBg,
    required this.filterOnFg,
    required this.filterOffBg,
    required this.filterOffBorder,
    required this.filterOffFg,
    required this.filterCountOn,
    required this.filterCountOff,
    required this.fabBg,
    required this.fabFg,
    required this.navBg,
    required this.navIndicator,
    required this.navActive,
    required this.navIdle,
  });

  /// Behind the lists.
  final Color background;

  /// A task card, the capacity pill and other raised surfaces.
  final Color card;

  /// The shadow of a card; none in the dark theme.
  final List<BoxShadow> cardShadow;

  /// Titles and body text.
  final Color title;

  /// The struck-through title of a done task.
  final Color titleDone;

  /// Secondary text: dates, counters, section headers.
  final Color muted;

  /// Text that must stand out a little more than [muted].
  final Color strong;

  /// The accent: progress, the Done button, today in the Plan.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// The empty part of the progress bar.
  final Color track;

  /// Repeat and planned-day chips.
  final Color neutralChipBg;
  final Color neutralChipFg;

  /// Text and icons of the quiet chips of a task card (card v2, T-1103):
  /// every chip but a loud priority and "At risk", on [neutralChipBg].
  final Color metaText;

  /// The text "+ Over plan" of a task card (T-1103), on [neutralChipBg].
  final Color metaExtra;

  /// The priority dot of a done task (T-1103).
  final Color priorityDotDone;

  /// The notes block of a task card (T-1103), and the text of its notes.
  final Color notesBg;
  final Color notesText;

  /// Focus and pin chips (before card v2; still in the theme).
  final Color accentChipBg;
  final Color accentChipFg;

  /// The "over plan" chip.
  final Color extraChipBg;
  final Color extraChipFg;

  /// Overdue, at risk.
  final Color alert;

  /// The "Completed" button of a done task.
  final Color doneButtonBg;
  final Color doneButtonFg;

  /// The capacity pill of a day in the Plan, and over capacity.
  final Color capPillBg;
  final Color capPillFg;
  final Color capOverBg;
  final Color capOverFg;

  /// A free slot dot in the capacity pill.
  final Color dotOff;

  /// The dashed border of the free slots of a day.
  final Color freeBorder;

  /// The name of today in the Plan.
  final Color todayName;

  /// Filter chips of the Tasks screen, selected and not.
  final Color filterOnBg;
  final Color filterOnFg;
  final Color filterOffBg;
  final Color filterOffBorder;
  final Color filterOffFg;
  final Color filterCountOn;
  final Color filterCountOff;

  /// The add button.
  final Color fabBg;
  final Color fabFg;

  /// The bottom navigation.
  final Color navBg;
  final Color navIndicator;
  final Color navActive;
  final Color navIdle;

  /// The colours of the theme of [context].
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  /// The colours for [brightness].
  static AppColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static const light = AppColors(
    background: Color(0xFFF3F4F6),
    card: Color(0xFFFFFFFF),
    cardShadow: [
      BoxShadow(color: Color(0x0F111827), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0A111827), blurRadius: 8, offset: Offset(0, 2)),
    ],
    title: Color(0xFF111827),
    titleDone: Color(0xFF6B7280),
    muted: Color(0xFF4B5563),
    strong: Color(0xFF374151),
    accent: Color(0xFF4F46E5),
    onAccent: Color(0xFFFFFFFF),
    track: Color(0xFFE5E7EB),
    neutralChipBg: Color(0xFFF3F4F6),
    neutralChipFg: Color(0xFF374151),
    metaText: Color(0xFF5F6673),
    metaExtra: Color(0xFF92400E),
    priorityDotDone: Color(0xFFD1D5DB),
    notesBg: Color(0xFFF6F7F9),
    notesText: Color(0xFF374151),
    accentChipBg: Color(0xFFE0E7FF),
    accentChipFg: Color(0xFF3730A3),
    extraChipBg: Color(0xFFFEF3C7),
    extraChipFg: Color(0xFF92400E),
    alert: Color(0xFFB91C1C),
    doneButtonBg: Color(0xFFE5E7EB),
    doneButtonFg: Color(0xFF374151),
    capPillBg: Color(0xFFFFFFFF),
    capPillFg: Color(0xFF374151),
    capOverBg: Color(0xFFFEE2E2),
    capOverFg: Color(0xFFB91C1C),
    dotOff: Color(0xFFD1D5DB),
    freeBorder: Color(0xFFC4C8D0),
    todayName: Color(0xFF3730A3),
    filterOnBg: Color(0xFFE0E7FF),
    filterOnFg: Color(0xFF1E1B4B),
    filterOffBg: Color(0xFFFFFFFF),
    filterOffBorder: Color(0xFFC4C8D0),
    filterOffFg: Color(0xFF374151),
    filterCountOn: Color(0xFF3730A3),
    filterCountOff: Color(0xFF6B7280),
    fabBg: Color(0xFFE0E7FF),
    fabFg: Color(0xFF312E81),
    navBg: Color(0xFFFFFFFF),
    navIndicator: Color(0xFFE0E7FF),
    navActive: Color(0xFF111827),
    navIdle: Color(0xFF4B5563),
  );

  static const dark = AppColors(
    background: Color(0xFF0F1115),
    card: Color(0xFF1A1D24),
    cardShadow: [],
    title: Color(0xFFF9FAFB),
    titleDone: Color(0xFF9CA3AF),
    muted: Color(0xFF9CA3AF),
    strong: Color(0xFFD1D5DB),
    accent: Color(0xFFA5B4FC),
    onAccent: Color(0xFF1E1B4B),
    track: Color(0xFF262A33),
    neutralChipBg: Color(0xFF262A33),
    neutralChipFg: Color(0xFFD1D5DB),
    metaText: Color(0xFF9CA3AF),
    metaExtra: Color(0xFFE3BC4E),
    priorityDotDone: Color(0xFF4B5563),
    notesBg: Color(0xFF20242C),
    notesText: Color(0xFFD1D5DB),
    accentChipBg: Color(0x29A5B4FC),
    accentChipFg: Color(0xFFC7D2FE),
    extraChipBg: Color(0x29FBBF24),
    extraChipFg: Color(0xFFFCD34D),
    alert: Color(0xFFFCA5A5),
    doneButtonBg: Color(0xFF2E333D),
    doneButtonFg: Color(0xFFD1D5DB),
    capPillBg: Color(0xFF1A1D24),
    capPillFg: Color(0xFFD1D5DB),
    capOverBg: Color(0x2EF87171),
    capOverFg: Color(0xFFFCA5A5),
    dotOff: Color(0xFF3A3F4A),
    freeBorder: Color(0xFF3A3F4A),
    todayName: Color(0xFFC7D2FE),
    filterOnBg: Color(0xFF3A4152),
    filterOnFg: Color(0xFFF3F4F6),
    filterOffBg: Color(0x00000000),
    filterOffBorder: Color(0xFF3A3F4A),
    filterOffFg: Color(0xFFD1D5DB),
    filterCountOn: Color(0xFFC7D2FE),
    filterCountOff: Color(0xFF9CA3AF),
    fabBg: Color(0xFF3B4A8A),
    fabFg: Color(0xFFE0E7FF),
    navBg: Color(0xFF1A1D24),
    navIndicator: Color(0xFF3A4152),
    navActive: Color(0xFFF3F4F6),
    navIdle: Color(0xFF9CA3AF),
  );

  /// The theme has no editable copy: it is one of two fixed sets.
  @override
  AppColors copyWith() => this;

  /// Theme changes switch at once: the sets are not blended.
  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t >= 0.5 ? other : this;
}

/// Sizes of the redesign in logical pixels (D22).
abstract final class AppDims {
  static const listPadding = 16.0;

  /// Around a task card in a list: the side margins and the gap below.
  static const cardMargin = EdgeInsets.fromLTRB(16, 0, 16, 10);
  static const headerPadding = EdgeInsets.fromLTRB(20, 8, 20, 14);
  static const cardSpacing = 10.0;

  static const cardRadius = 18.0;
  static const cardPadding = EdgeInsets.fromLTRB(16, 14, 14, 12);
  static const cardGap = 10.0;
  static const doneOpacity = 0.62;
  static const doneFade = Duration(milliseconds: 200);

  static const chipHeight = 24.0;
  static const chipRadius = 12.0;
  static const chipHPadding = 10.0;
  static const chipSpacing = 6.0;
  static const chipIcon = 13.0;
  static const priorityDot = 8.0;

  static const notesRadius = 12.0;
  static const notesAnim = Duration(milliseconds: 200);

  static const doneButtonHeight = 40.0;
  static const doneButtonMinWidth = 116.0;
  static const doneButtonBorder = 1.5;

  static const progressHeight = 8.0;
  static const progressAnim = Duration(milliseconds: 300);

  static const capPillHeight = 28.0;
  static const capDot = 6.0;
  static const freeSlotHeight = 48.0;

  static const minTapTarget = 44.0;
  static const navBarHeight = 80.0;
  static const fabRadius = 16.0;

  /// Room below the last card so the add button and the navigation do not
  /// cover it.
  static const listBottomPadding = 168.0;
}

/// The two colours of a priority chip: a light tint of the priority colour
/// and the colour itself made dark (light theme) or light (dark theme)
/// enough to read on that tint (D1, D22).
///
/// The priority colour stays the app's own (`PriorityLabels.color`), so all
/// three scales keep their levels; only the shade depends on the theme.
@immutable
class PriorityShade {
  const PriorityShade(this.background, this.foreground);

  /// The shade of [color] in a theme of [brightness], on a card of [card].
  factory PriorityShade.of(Color color, Brightness brightness, Color card) {
    final hsl = HSLColor.fromColor(color);
    if (brightness == Brightness.light) {
      final background = hsl
          .withLightness(0.93)
          .withSaturation(hsl.saturation.clamp(0, 0.85))
          .toColor();
      var text = hsl.withLightness(hsl.lightness.clamp(0, 0.38));
      while (contrastRatio(text.toColor(), background) < minContrast &&
          text.lightness > 0.05) {
        text = text.withLightness(text.lightness - 0.02);
      }
      return PriorityShade(background, text.toColor());
    }
    final background = Color.alphaBlend(color.withValues(alpha: 0.18), card);
    var text = hsl.withLightness(hsl.lightness.clamp(0.75, 1));
    while (contrastRatio(text.toColor(), background) < minContrast &&
        text.lightness < 0.95) {
      text = text.withLightness(text.lightness + 0.02);
    }
    return PriorityShade(background, text.toColor());
  }

  /// The least contrast of text on its background (WCAG AA).
  static const minContrast = 4.5;

  final Color background;
  final Color foreground;

  @override
  bool operator ==(Object other) =>
      other is PriorityShade &&
      other.background == background &&
      other.foreground == foreground;

  @override
  int get hashCode => Object.hash(background, foreground);
}

/// The WCAG contrast ratio of two colours, 1 to 21. A translucent colour
/// counts as it is, so blend it over its surface first.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}
