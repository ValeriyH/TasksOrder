import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/converters.dart';
import 'package:tasks_order/domain/model/local_date.dart';

void main() {
  group('LocalDateConverter', () {
    const converter = LocalDateConverter();

    test('writes ISO text and reads it back', () {
      final date = LocalDate(2024, 2, 29);
      expect(converter.toSql(date), '2024-02-29');
      expect(converter.fromSql('2024-02-29'), date);
    });

    test('text order is date order', () {
      final earlier = converter.toSql(LocalDate(2026, 9, 30));
      final later = converter.toSql(LocalDate(2026, 10, 1));
      expect(earlier.compareTo(later), isNegative);
    });
  });

  group('UtcMillisConverter', () {
    const converter = UtcMillisConverter();

    test('reads a UTC instant', () {
      final read = converter.fromSql(1763000000123);
      expect(read.isUtc, isTrue);
      expect(read.millisecondsSinceEpoch, 1763000000123);
    });

    test('a local time is stored as the same instant', () {
      final utc = DateTime.utc(2026, 11, 13, 10, 30);
      expect(converter.toSql(utc.toLocal()), utc.millisecondsSinceEpoch);
    });

    test('microseconds are dropped', () {
      final precise = DateTime.utc(2026, 11, 13, 10, 30, 0, 5, 700);
      expect(
        converter.fromSql(converter.toSql(precise)),
        DateTime.utc(2026, 11, 13, 10, 30, 0, 5),
      );
    });
  });

  group('IntListConverter', () {
    const converter = IntListConverter();

    test('writes a JSON array and reads it back', () {
      expect(converter.toSql([1, 1, 1, 1, 1, 3, 0]), '[1,1,1,1,1,3,0]');
      expect(converter.fromSql('[1,1,1,1,1,3,0]'), [1, 1, 1, 1, 1, 3, 0]);
    });

    test('the list read from the database cannot be changed', () {
      expect(() => converter.fromSql('[1,2]').add(3), throwsUnsupportedError);
    });
  });
}
