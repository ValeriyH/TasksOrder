import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/db/converters.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';

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

  group('RecurrenceConverter (D20)', () {
    const converter = RecurrenceConverter();
    final rules = <String, Recurrence>{
      '{"kind":"interval","every":1,"unit":"month","afterDone":false,'
          '"anchor":"2026-11-30"}': Recurrence.interval(
        every: 1,
        unit: RecurrenceUnit.month,
        anchor: LocalDate(2026, 11, 30),
      ),
      '{"kind":"interval","every":30,"unit":"day","afterDone":true}':
          Recurrence.interval(
            every: 30,
            unit: RecurrenceUnit.day,
            afterDone: true,
          ),
      '{"kind":"weekdays","days":[0,2,4]}': Recurrence.weekdays(const {
        4,
        0,
        2,
      }),
    };

    test('writes the JSON of docs/03 Data Model.md and reads it back', () {
      for (final MapEntry(key: json, value: rule) in rules.entries) {
        expect(converter.toSql(rule), json);
        expect(converter.fromSql(json), rule);
      }
    });

    test('a broken rule is a FormatException', () {
      const impossibleAnchor =
          '{"kind":"interval","every":1,"unit":"day","afterDone":false,'
          '"anchor":"2026-02-30"}';
      for (final json in [
        '{"kind":"monthly"}',
        '{"kind":"interval","every":0,"unit":"day","afterDone":true}',
        '{"kind":"interval","every":1,"unit":"hour","afterDone":true}',
        '{"kind":"interval","every":1,"unit":"day","afterDone":false}',
        '{"kind":"interval","every":"1","unit":"day","afterDone":true}',
        '{"kind":"weekdays","days":[]}',
        '{"kind":"weekdays","days":[7]}',
        impossibleAnchor,
      ]) {
        expect(
          () => converter.fromSql(json),
          throwsFormatException,
          reason: json,
        );
      }
    });
  });
}
