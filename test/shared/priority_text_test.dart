import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final uk = lookupAppLocalizations(const Locale('uk'));

  test('every priority of every scale has a name in both languages', () {
    var count = 0;
    for (final l10n in [en, uk]) {
      for (final scale in PriorityLabels.scales) {
        for (var priority = 1; priority <= scale; priority++) {
          expect(priorityName(l10n, priority, scale), isNotEmpty);
          count++;
        }
      }
    }
    expect(count, 2 * PriorityLabels.allKeys.length);
  });

  test('the names follow the tables of D1', () {
    expect(priorityName(en, 1, 3), 'Critical');
    expect(priorityName(en, 3, 3), 'Low');
    expect(priorityName(en, 3, 5), 'Normal');
    expect(priorityName(en, 5, 5), 'Someday');
    expect(priorityName(en, 1, 10), 'Catastrophic');
    expect(priorityName(en, 10, 10), 'Never');
    expect(priorityName(uk, 2, 5), 'Високий');
    expect(priorityName(uk, 9, 10), 'Хтозна-коли');
  });

  test('a priority is shown as "Label (n)"', () {
    expect(priorityLabel(en, 2, 5), 'High (2)');
    expect(priorityLabel(uk, 3, 5), 'Звичайний (3)');
  });

  test('colours come from the domain gradient', () {
    expect(priorityColor(1, 5), const Color(PriorityLabels.highestColor));
    expect(priorityColor(3, 5), const Color(PriorityLabels.middleColor));
    expect(priorityColor(5, 5), const Color(PriorityLabels.lowestColor));
  });

  test('a priority outside the scale is an error', () {
    expect(() => priorityName(en, 4, 3), throwsArgumentError);
  });
}
