import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/app/theme.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';

void main() {
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};

  /// [fg] on [bg], each blended over [under] when translucent.
  double contrastOver(Color fg, Color bg, Color under) {
    final base = Color.alphaBlend(bg, under);
    return contrastRatio(Color.alphaBlend(fg, base), base);
  }

  group('priority chips (D1, D22)', () {
    for (final MapEntry(key: name, value: brightness) in themes.entries) {
      final c = AppColors.forBrightness(brightness);
      for (final scale in PriorityLabels.scales) {
        test('every level of scale $scale reads in the $name theme', () {
          for (final level in PriorityLabels.levels(scale)) {
            final shade = PriorityShade.of(
              Color(PriorityLabels.color(level, scale)),
              brightness,
              c.card,
            );
            expect(
              contrastRatio(shade.foreground, shade.background),
              greaterThanOrEqualTo(PriorityShade.minContrast),
              reason: 'level $level',
            );
          }
        });
      }

      test('the levels of scale 5 keep different hues in the $name theme', () {
        final shades = {
          for (final level in PriorityLabels.levels(5))
            PriorityShade.of(
              Color(PriorityLabels.color(level, 5)),
              brightness,
              c.card,
            ).foreground,
        };
        expect(shades, hasLength(5));
      });
    }
  });

  group('text tokens (D22)', () {
    for (final MapEntry(key: name, value: brightness) in themes.entries) {
      final c = AppColors.forBrightness(brightness);
      final pairs = {
        'title on background': (c.title, c.background),
        'title on card': (c.title, c.card),
        'muted on background': (c.muted, c.background),
        'muted on card': (c.muted, c.card),
        'title of a done task on card': (c.titleDone, c.card),
        'accent on card': (c.accent, c.card),
        'today name on background': (c.todayName, c.background),
        'alert on card': (c.alert, c.card),
        'neutral chip': (c.neutralChipFg, c.neutralChipBg),
        'accent chip': (c.accentChipFg, c.accentChipBg),
        'over plan chip': (c.extraChipFg, c.extraChipBg),
        'completed button': (c.doneButtonFg, c.doneButtonBg),
        'capacity pill': (c.capPillFg, c.capPillBg),
        'capacity pill over': (c.capOverFg, c.capOverBg),
        'filter on': (c.filterOnFg, c.filterOnBg),
        'filter on, count': (c.filterCountOn, c.filterOnBg),
        'filter off': (c.filterOffFg, c.filterOffBg),
        'filter off, count': (c.filterCountOff, c.filterOffBg),
        'add button': (c.fabFg, c.fabBg),
        'navigation, active': (c.navActive, c.navIndicator),
        'navigation, idle': (c.navIdle, c.navBg),
        'on accent': (c.onAccent, c.accent),
      };
      for (final MapEntry(key: what, value: (fg, bg)) in pairs.entries) {
        test('$what reads in the $name theme', () {
          expect(
            contrastOver(fg, bg, c.background),
            greaterThanOrEqualTo(PriorityShade.minContrast),
          );
        });
      }
    }
  });

  group('appTheme (ADR-23)', () {
    for (final MapEntry(key: name, value: brightness) in themes.entries) {
      test('the $name theme carries its colours', () {
        final theme = appTheme(brightness);
        final c = AppColors.forBrightness(brightness);
        expect(theme.brightness, brightness);
        expect(theme.extension<AppColors>(), same(c));
        expect(theme.scaffoldBackgroundColor, c.background);
        expect(theme.colorScheme.primary, c.accent);
        expect(theme.navigationBarTheme.backgroundColor, c.navBg);
        expect(theme.floatingActionButtonTheme.backgroundColor, c.fabBg);
      });
    }
  });

  test(
    'contrastRatio is 21 for black on white and 1 for a colour on itself',
    () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        contrastRatio(const Color(0xFF4F46E5), const Color(0xFF4F46E5)),
        1,
      );
    },
  );
}
