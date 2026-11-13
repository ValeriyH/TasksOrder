import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';

void main() {
  group('construction', () {
    test('keeps year, month and day', () {
      final d = LocalDate(2026, 11, 13);
      expect((d.year, d.month, d.day), (2026, 11, 13));
    });

    test('rejects impossible dates', () {
      expect(() => LocalDate(2026, 2, 30), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
      expect(() => LocalDate(2026, 0, 1), throwsArgumentError);
      expect(() => LocalDate(2026, 4, 31), throwsArgumentError);
      expect(() => LocalDate(2026, 1, 0), throwsArgumentError);
      expect(() => LocalDate(0, 1, 1), throwsArgumentError);
      expect(() => LocalDate(10000, 1, 1), throwsArgumentError);
    });

    test('leap day exists only in leap years', () {
      expect(LocalDate(2028, 2, 29).day, 29);
      expect(LocalDate(2000, 2, 29).day, 29);
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2100, 2, 29), throwsArgumentError);
    });

    test('fromDateTime takes the calendar fields and drops the time', () {
      expect(
        LocalDate.fromDateTime(DateTime(2026, 11, 13, 23, 59, 59)),
        LocalDate(2026, 11, 13),
      );
      expect(
        LocalDate.fromDateTime(DateTime.utc(2026, 1, 1)),
        LocalDate(2026, 1, 1),
      );
    });
  });

  group('todayFor', () {
    test('with a midnight start it is the calendar date', () {
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13), 0),
        LocalDate(2026, 11, 13),
      );
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 23, 59, 59), 0),
        LocalDate(2026, 11, 13),
      );
    });

    test('before the day start it is still yesterday', () {
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 3, 59, 59, 999), 4),
        LocalDate(2026, 11, 12),
      );
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 0, 30), 4),
        LocalDate(2026, 11, 12),
      );
    });

    test('at the day start the new day begins', () {
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 4), 4),
        LocalDate(2026, 11, 13),
      );
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 22), 4),
        LocalDate(2026, 11, 13),
      );
    });

    test('rolls back over month and year boundaries', () {
      expect(
        LocalDate.todayFor(DateTime(2027, 1, 1, 2), 4),
        LocalDate(2026, 12, 31),
      );
      expect(
        LocalDate.todayFor(DateTime(2028, 3, 1, 1), 4),
        LocalDate(2028, 2, 29),
      );
    });

    test('a late start keeps most of the day on yesterday', () {
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 22, 59), 23),
        LocalDate(2026, 11, 12),
      );
      expect(
        LocalDate.todayFor(DateTime(2026, 11, 13, 23), 23),
        LocalDate(2026, 11, 13),
      );
    });

    test('rejects an hour outside 0..23', () {
      final now = DateTime(2026, 11, 13, 12);
      expect(() => LocalDate.todayFor(now, -1), throwsRangeError);
      expect(() => LocalDate.todayFor(now, 24), throwsRangeError);
    });
  });

  group('addDays', () {
    test('zero returns an equal date', () {
      expect(LocalDate(2026, 11, 13).addDays(0), LocalDate(2026, 11, 13));
    });

    test('rolls over the end of a month', () {
      expect(LocalDate(2026, 1, 31).addDays(1), LocalDate(2026, 2, 1));
      expect(LocalDate(2026, 4, 30).addDays(1), LocalDate(2026, 5, 1));
      expect(LocalDate(2026, 5, 1).addDays(-1), LocalDate(2026, 4, 30));
    });

    test('rolls over the end of a year', () {
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2027, 1, 1).addDays(-1), LocalDate(2026, 12, 31));
    });

    test('handles February in leap and common years', () {
      expect(LocalDate(2028, 2, 28).addDays(1), LocalDate(2028, 2, 29));
      expect(LocalDate(2028, 2, 29).addDays(1), LocalDate(2028, 3, 1));
      expect(LocalDate(2028, 3, 1).addDays(-1), LocalDate(2028, 2, 29));
      expect(LocalDate(2026, 2, 28).addDays(1), LocalDate(2026, 3, 1));
    });

    test('crosses many months at once', () {
      expect(LocalDate(2026, 11, 13).addDays(365), LocalDate(2027, 11, 13));
      expect(LocalDate(2027, 11, 13).addDays(366), LocalDate(2028, 11, 13));
      expect(LocalDate(2026, 11, 13).addDays(-365), LocalDate(2025, 11, 13));
    });

    test('is not affected by daylight saving switches', () {
      // EU switches: 2026-03-29 and 2026-10-25.
      expect(LocalDate(2026, 3, 28).addDays(2), LocalDate(2026, 3, 30));
      expect(LocalDate(2026, 10, 24).addDays(2), LocalDate(2026, 10, 26));
    });
  });

  group('daysUntil', () {
    test('is zero for the same day', () {
      expect(LocalDate(2026, 11, 13).daysUntil(LocalDate(2026, 11, 13)), 0);
    });

    test('is positive for later and negative for earlier dates', () {
      final d = LocalDate(2026, 11, 13);
      expect(d.daysUntil(LocalDate(2026, 11, 20)), 7);
      expect(d.daysUntil(LocalDate(2026, 11, 6)), -7);
    });

    test('counts across month, year and leap day', () {
      expect(LocalDate(2026, 12, 31).daysUntil(LocalDate(2027, 1, 1)), 1);
      expect(LocalDate(2028, 2, 28).daysUntil(LocalDate(2028, 3, 1)), 2);
      expect(LocalDate(2026, 2, 28).daysUntil(LocalDate(2026, 3, 1)), 1);
      expect(LocalDate(2028, 1, 1).daysUntil(LocalDate(2029, 1, 1)), 366);
      expect(LocalDate(2026, 1, 1).daysUntil(LocalDate(2027, 1, 1)), 365);
    });

    test('counts across daylight saving switches', () {
      expect(LocalDate(2026, 3, 28).daysUntil(LocalDate(2026, 3, 30)), 2);
      expect(LocalDate(2026, 10, 24).daysUntil(LocalDate(2026, 10, 26)), 2);
    });

    test('is the inverse of addDays', () {
      final d = LocalDate(2026, 11, 13);
      for (final n in [-800, -31, -1, 0, 1, 30, 59, 366, 1500]) {
        expect(d.daysUntil(d.addDays(n)), n);
      }
    });

    test('works before 1970', () {
      expect(LocalDate(1969, 12, 31).daysUntil(LocalDate(1970, 1, 1)), 1);
      expect(LocalDate(1970, 1, 1).addDays(-1), LocalDate(1969, 12, 31));
    });
  });

  group('weekday', () {
    test('is Monday = 0 .. Sunday = 6', () {
      // 2026-11-09 is a Monday.
      for (var i = 0; i < 7; i++) {
        expect(LocalDate(2026, 11, 9).addDays(i).weekday, i);
      }
    });

    test('matches known dates', () {
      expect(LocalDate(2026, 11, 13).weekday, 4); // Friday
      expect(LocalDate(2028, 2, 29).weekday, 1); // Tuesday
      expect(LocalDate(2000, 1, 1).weekday, 5); // Saturday
      expect(LocalDate(1970, 1, 1).weekday, 3); // Thursday
      expect(LocalDate(1969, 12, 28).weekday, 6); // Sunday
    });
  });

  group('ordering', () {
    final a = LocalDate(2026, 11, 13);
    final b = LocalDate(2026, 12, 1);
    final c = LocalDate(2027, 1, 1);

    test('compareTo orders by year, then month, then day', () {
      expect(a.compareTo(b), isNegative);
      expect(b.compareTo(a), isPositive);
      expect(b.compareTo(c), isNegative);
      expect(a.compareTo(LocalDate(2026, 11, 13)), 0);
    });

    test('sorts chronologically', () {
      expect([c, a, b]..sort(), [a, b, c]);
    });

    test('comparison operators', () {
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= LocalDate(2026, 11, 13), isTrue);
      expect(a >= LocalDate(2026, 11, 13), isTrue);
      expect(a > b, isFalse);
      expect(c < b, isFalse);
    });
  });

  group('equality', () {
    test('equal dates are equal and share a hash code', () {
      final a = LocalDate(2026, 11, 13);
      final b = LocalDate(2026, 11, 13);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });

    test('different dates are not equal', () {
      expect(LocalDate(2026, 11, 13) == LocalDate(2026, 11, 14), isFalse);
      expect(LocalDate(2026, 11, 13) == LocalDate(2026, 10, 13), isFalse);
      expect(LocalDate(2026, 11, 13) == LocalDate(2025, 11, 13), isFalse);
    });

    test('works as a map key', () {
      final map = {LocalDate(2026, 11, 13): 'x'};
      expect(map[LocalDate(2026, 11, 13)], 'x');
      expect(map[LocalDate(2026, 11, 14)], isNull);
    });
  });

  group('ISO format', () {
    test('toIso pads month, day and year', () {
      expect(LocalDate(2026, 11, 13).toIso(), '2026-11-13');
      expect(LocalDate(2026, 1, 5).toIso(), '2026-01-05');
      expect(LocalDate(987, 6, 5).toIso(), '0987-06-05');
    });

    test('toString is the ISO form', () {
      expect(LocalDate(2026, 1, 5).toString(), '2026-01-05');
    });

    test('parse reads yyyy-MM-dd', () {
      expect(LocalDate.parse('2026-11-13'), LocalDate(2026, 11, 13));
      expect(LocalDate.parse('2028-02-29'), LocalDate(2028, 2, 29));
    });

    test('parse round-trips toIso', () {
      for (final d in [
        LocalDate(2026, 1, 1),
        LocalDate(2026, 12, 31),
        LocalDate(2028, 2, 29),
        LocalDate(1999, 9, 9),
      ]) {
        expect(LocalDate.parse(d.toIso()), d);
      }
    });

    test('parse rejects malformed and impossible input', () {
      for (final s in [
        '',
        '2026-1-5',
        '2026/11/13',
        '13-11-2026',
        '2026-11-13T00:00:00',
        ' 2026-11-13',
        '2026-11-13\n',
        '2026-02-30',
        '2026-13-01',
        '2026-00-10',
        '2026-02-29',
        '0000-01-01',
      ]) {
        expect(() => LocalDate.parse(s), throwsFormatException, reason: s);
      }
    });

    test('tryParse returns null instead of throwing', () {
      expect(LocalDate.tryParse('2026-11-13'), LocalDate(2026, 11, 13));
      expect(LocalDate.tryParse('2026-02-30'), isNull);
      expect(LocalDate.tryParse('nope'), isNull);
    });
  });
}
