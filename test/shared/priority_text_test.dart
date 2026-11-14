import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final uk = lookupAppLocalizations(const Locale('uk'));

  test('every level of every scale has a name in both languages', () {
    var count = 0;
    for (final l10n in [en, uk]) {
      for (final scale in PriorityLabels.scales) {
        for (final priority in PriorityLabels.levels(scale)) {
          expect(priorityName(l10n, priority, scale), isNotEmpty);
          count++;
        }
      }
    }
    expect(count, 2 * PriorityLabels.allKeys.length);
  });

  test('the names follow the tables of D1', () {
    expect(priorityName(en, 2, 3), 'Critical');
    expect(priorityName(en, 7, 3), 'Low');
    expect(priorityName(en, 5, 5), 'Normal');
    expect(priorityName(en, 8, 5), 'Someday');
    expect(priorityName(en, 1, 10), 'Catastrophic');
    expect(priorityName(en, 10, 10), 'Never');
    expect(priorityName(uk, 3, 5), 'Високий');
    expect(priorityName(uk, 9, 10), 'Хтозна-коли');
  });

  test('a level keeps its name when the scale changes (ADR-17)', () {
    for (final l10n in [en, uk]) {
      for (final level in [2, 5, 7]) {
        final names = {
          for (final scale in PriorityLabels.scales)
            priorityName(l10n, level, scale),
        };
        expect(names, hasLength(1), reason: '$level: $names');
      }
      for (final level in [3, 8]) {
        expect(
          priorityName(l10n, level, 5),
          priorityName(l10n, level, 10),
          reason: '$level',
        );
      }
    }
  });

  test('a level the scale does not offer reads as the nearest one', () {
    expect(priorityName(en, 4, 5), 'High');
    expect(priorityName(en, 10, 5), 'Someday');
    expect(priorityName(en, 1, 3), 'Critical');
  });

  test('colours come from the domain gradient', () {
    expect(priorityColor(2, 5), const Color(PriorityLabels.highestColor));
    expect(priorityColor(5, 5), const Color(PriorityLabels.middleColor));
    expect(priorityColor(8, 5), const Color(PriorityLabels.lowestColor));
  });
}
