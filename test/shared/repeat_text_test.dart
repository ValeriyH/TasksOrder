import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/repeat_text.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final uk = lookupAppLocalizations(const Locale('uk'));
  final anchor = LocalDate(2026, 11, 13);

  Recurrence every(int n, RecurrenceUnit unit) =>
      Recurrence.interval(every: n, unit: unit, anchor: anchor);
  Recurrence after(int n, RecurrenceUnit unit) =>
      Recurrence.interval(every: n, unit: unit, afterDone: true);

  test('by schedule', () {
    expect(repeatSummary(en, every(1, RecurrenceUnit.day)), 'Every day');
    expect(repeatSummary(en, every(3, RecurrenceUnit.day)), 'Every 3 days');
    expect(repeatSummary(en, every(1, RecurrenceUnit.month)), 'Every month');
    expect(repeatSummary(uk, every(1, RecurrenceUnit.week)), 'Щотижня');
    expect(repeatSummary(uk, every(2, RecurrenceUnit.week)), 'Кожні 2 тижні');
    expect(
      repeatSummary(uk, every(5, RecurrenceUnit.month)),
      'Кожні 5 місяців',
    );
    expect(repeatSummary(uk, every(21, RecurrenceUnit.day)), 'Кожен 21 день');
    expect(repeatSummary(uk, every(1, RecurrenceUnit.year)), 'Щороку');
  });

  test('from completion', () {
    expect(
      repeatSummary(en, after(30, RecurrenceUnit.day)),
      '30 days after it is done',
    );
    expect(
      repeatSummary(uk, after(5, RecurrenceUnit.day)),
      'Через 5 днів після виконання',
    );
    expect(
      repeatSummary(uk, after(1, RecurrenceUnit.month)),
      'Через 1 місяць після виконання',
    );
  });

  test('weekdays in week order', () {
    final rule = Recurrence.weekdays(const {4, 0, 2});

    expect(repeatSummary(en, rule), 'Mon, Wed, Fri');
    expect(repeatSummary(uk, rule), 'Пн, Ср, Пт');
  });
}
