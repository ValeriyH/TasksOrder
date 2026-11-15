import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';

/// T-701: the repeat rule of D20 and its date math.
void main() {
  LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

  Recurrence schedule(int every, RecurrenceUnit unit, LocalDate anchor) =>
      Recurrence.interval(every: every, unit: unit, anchor: anchor);

  List<LocalDate> dates(Recurrence rule, LocalDate base, LocalDate until) =>
      rule.datesAfter(base, until).toList();

  group('validation', () {
    test('every must be at least 1', () {
      expect(
        () => schedule(0, RecurrenceUnit.day, d(2026, 1, 1)),
        throwsArgumentError,
      );
    });

    test(
      'a rule by schedule needs an anchor, one from completion has none',
      () {
        expect(
          () => Recurrence.interval(every: 1, unit: RecurrenceUnit.week),
          throwsArgumentError,
        );
        expect(
          () => Recurrence.interval(
            every: 1,
            unit: RecurrenceUnit.week,
            afterDone: true,
            anchor: d(2026, 1, 1),
          ),
          throwsArgumentError,
        );
      },
    );

    test('weekdays must be a non-empty set within 0..6', () {
      expect(() => Recurrence.weekdays(const {}), throwsArgumentError);
      expect(() => Recurrence.weekdays(const {7}), throwsArgumentError);
      expect(() => Recurrence.weekdays(const {-1}), throwsArgumentError);
    });

    test('equal rules are equal', () {
      expect(
        schedule(2, RecurrenceUnit.week, d(2026, 1, 5)),
        schedule(2, RecurrenceUnit.week, d(2026, 1, 5)),
      );
      expect(
        Recurrence.weekdays(const {4, 0, 2}),
        Recurrence.weekdays(const {0, 2, 4}),
      );
      expect(
        Recurrence.weekdays(const {0}),
        isNot(Recurrence.weekdays(const {1})),
      );
    });
  });

  group('monthly by schedule: the day of the anchor, the month end', () {
    for (final day in [29, 30, 31]) {
      test('anchor Jan $day over a common and a leap year', () {
        final rule = schedule(1, RecurrenceUnit.month, d(2027, 1, day));

        // 2027 is a common year, 2028 a leap year.
        expect(dates(rule, d(2027, 1, day), d(2027, 4, 30)), [
          d(2027, 2, 28),
          d(2027, 3, day),
          d(2027, 4, day == 31 ? 30 : day),
        ]);
        expect(rule.firstAfter(d(2028, 1, 31)), d(2028, 2, 29));
        expect(
          rule.firstAfter(d(2028, 2, 29)),
          d(2028, 3, day),
          reason: 'each date comes from the anchor, not from the one before',
        );
      });
    }
  });

  test('yearly from Feb 29', () {
    final rule = schedule(1, RecurrenceUnit.year, d(2028, 2, 29));

    expect(dates(rule, d(2028, 2, 29), d(2033, 1, 1)), [
      d(2029, 2, 28),
      d(2030, 2, 28),
      d(2031, 2, 28),
      d(2032, 2, 29),
    ]);
  });

  test('every 2 weeks keeps its phase', () {
    // Monday 2026-11-02.
    final rule = schedule(2, RecurrenceUnit.week, d(2026, 11, 2));

    expect(rule.firstAfter(d(2026, 11, 2)), d(2026, 11, 16));
    // Late by ten days: the next one is still on the two-week grid.
    expect(rule.firstAfter(d(2026, 11, 26)), d(2026, 11, 30));
    expect(rule.firstAfter(d(2027, 3, 1)), d(2027, 3, 8));
    expect(rule.firstAfter(d(2027, 3, 8)), d(2027, 3, 22));
  });

  test('every 3 days by schedule', () {
    final rule = schedule(3, RecurrenceUnit.day, d(2026, 11, 1));

    expect(dates(rule, d(2026, 11, 2), d(2026, 11, 12)), [
      d(2026, 11, 4),
      d(2026, 11, 7),
      d(2026, 11, 10),
    ]);
  });

  test('a date before the anchor gives the anchor first', () {
    final rule = schedule(1, RecurrenceUnit.month, d(2026, 12, 15));

    expect(rule.firstAfter(d(2026, 11, 1)), d(2026, 12, 15));
  });

  group('weekdays', () {
    test('over the week end', () {
      // Mon, Wed, Fri; 2026-11-13 is a Friday.
      final rule = Recurrence.weekdays(const {0, 2, 4});

      expect(rule.firstAfter(d(2026, 11, 13)), d(2026, 11, 16));
      expect(dates(rule, d(2026, 11, 13), d(2026, 11, 22)), [
        d(2026, 11, 16),
        d(2026, 11, 18),
        d(2026, 11, 20),
      ]);
    });

    test('a single weekday is weekly', () {
      // Sunday.
      final rule = Recurrence.weekdays(const {6});

      expect(rule.firstAfter(d(2026, 11, 15)), d(2026, 11, 22));
      expect(rule.firstAfter(d(2026, 11, 14)), d(2026, 11, 15));
    });
  });

  group('from completion', () {
    test('adds the interval to the day it was done', () {
      final rule = Recurrence.interval(
        every: 30,
        unit: RecurrenceUnit.day,
        afterDone: true,
      );

      expect(rule.addTo(d(2026, 11, 15)), d(2026, 12, 15));
      expect(rule.isAfterDone, isTrue);
    });

    test('months from completion keep the month end', () {
      final rule = Recurrence.interval(
        every: 1,
        unit: RecurrenceUnit.month,
        afterDone: true,
      );

      expect(rule.addTo(d(2026, 1, 31)), d(2026, 2, 28));
    });

    test('the forecast repeats the interval', () {
      final rule = Recurrence.interval(
        every: 2,
        unit: RecurrenceUnit.week,
        afterDone: true,
      );

      expect(dates(rule, d(2026, 11, 2), d(2026, 12, 15)), [
        d(2026, 11, 16),
        d(2026, 11, 30),
        d(2026, 12, 14),
      ]);
    });

    test('firstAfter is the next date for a completion on that day', () {
      final rule = Recurrence.interval(
        every: 7,
        unit: RecurrenceUnit.day,
        afterDone: true,
      );

      expect(rule.firstAfter(d(2026, 11, 15)), d(2026, 11, 22));
    });
  });

  test('a rule by schedule cannot add to a date', () {
    final rule = schedule(1, RecurrenceUnit.week, d(2026, 11, 2));

    expect(() => rule.addTo(d(2026, 11, 2)), throwsStateError);
    expect(Recurrence.weekdays(const {0}).isAfterDone, isFalse);
  });

  test('datesAfter stops at until, inclusive', () {
    final rule = schedule(1, RecurrenceUnit.day, d(2026, 11, 1));

    expect(dates(rule, d(2026, 11, 1), d(2026, 11, 3)), [
      d(2026, 11, 2),
      d(2026, 11, 3),
    ]);
    expect(dates(rule, d(2026, 11, 3), d(2026, 11, 3)), isEmpty);
  });
}
