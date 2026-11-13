import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';

void main() {
  final isAssertionError = throwsA(isA<AssertionError>());

  group('Settings defaults', () {
    final s = Settings();

    test('match the data model', () {
      expect(s.priorityScale, 5);
      expect(s.weeklyCapacity, [1, 1, 1, 1, 1, 3, 0]);
      expect(s.maxOverflowPerDay, 1);
      expect(s.planningHorizonDays, 90);
      expect(s.urgencySoonDays, 7);
      expect(s.urgencyNearDays, 2);
      expect(s.focusVisibleLimit, 3);
      expect(s.dayStartHour, 0);
    });

    test('two default instances are equal', () {
      expect(Settings(), Settings());
      expect(Settings().hashCode, Settings().hashCode);
    });

    test('equality compares the capacity list by content', () {
      final a = Settings(weeklyCapacity: [2, 2, 2, 2, 2, 0, 0]);
      final b = Settings(weeklyCapacity: [2, 2, 2, 2, 2, 0, 0]);
      expect(a, b);
      expect(a, isNot(Settings()));
    });

    test('the capacity list cannot be modified in place', () {
      expect(() => s.weeklyCapacity[0] = 9, throwsUnsupportedError);
    });
  });

  group('Settings validation', () {
    test('priority scale must be 3, 5 or 10', () {
      for (final scale in [3, 5, 10]) {
        expect(Settings(priorityScale: scale).priorityScale, scale);
      }
      for (final scale in [0, 1, 4, 7, 11]) {
        expect(() => Settings(priorityScale: scale), isAssertionError);
      }
    });

    test('weekly capacity needs 7 non-negative values', () {
      expect(() => Settings(weeklyCapacity: [1, 1, 1]), isAssertionError);
      expect(
        () => Settings(weeklyCapacity: [1, 1, 1, 1, 1, 1, 1, 1]),
        isAssertionError,
      );
      expect(
        () => Settings(weeklyCapacity: [1, 1, 1, -1, 1, 1, 1]),
        isAssertionError,
      );
      expect(
        Settings(weeklyCapacity: [0, 0, 0, 0, 0, 0, 0]).weeklyCapacity,
        everyElement(0),
      );
    });

    test('overflow is 0..3', () {
      for (final overflow in [0, 1, 2, 3]) {
        expect(
          Settings(maxOverflowPerDay: overflow).maxOverflowPerDay,
          overflow,
        );
      }
      expect(() => Settings(maxOverflowPerDay: -1), isAssertionError);
      expect(() => Settings(maxOverflowPerDay: 4), isAssertionError);
    });

    test('horizon covers at least today', () {
      expect(Settings(planningHorizonDays: 1).planningHorizonDays, 1);
      expect(() => Settings(planningHorizonDays: 0), isAssertionError);
    });

    test('urgency thresholds satisfy 0 <= near <= soon', () {
      expect(Settings(urgencySoonDays: 0, urgencyNearDays: 0), isNotNull);
      expect(Settings(urgencySoonDays: 3, urgencyNearDays: 3), isNotNull);
      expect(
        () => Settings(urgencySoonDays: 1, urgencyNearDays: 2),
        isAssertionError,
      );
      expect(() => Settings(urgencyNearDays: -1), isAssertionError);
    });

    test('today visible limit is at least 1', () {
      expect(Settings(focusVisibleLimit: 1).focusVisibleLimit, 1);
      expect(() => Settings(focusVisibleLimit: 0), isAssertionError);
    });

    test('day start hour is 0..23', () {
      expect(Settings(dayStartHour: 23).dayStartHour, 23);
      expect(() => Settings(dayStartHour: -1), isAssertionError);
      expect(() => Settings(dayStartHour: 24), isAssertionError);
    });

    test('copyWith validates too', () {
      expect(() => Settings().copyWith(dayStartHour: 24), isAssertionError);
    });
  });

  group('DayOverride', () {
    final date = LocalDate(2026, 12, 25);

    test('keeps its fields', () {
      final o = DayOverride(date: date, capacity: 0, note: 'holiday');
      expect(o.date, date);
      expect(o.capacity, 0);
      expect(o.note, 'holiday');
    });

    test('note is optional', () {
      expect(DayOverride(date: date, capacity: 2).note, isNull);
    });

    test('has value equality', () {
      expect(
        DayOverride(date: date, capacity: 2),
        DayOverride(date: LocalDate(2026, 12, 25), capacity: 2),
      );
      expect(
        DayOverride(date: date, capacity: 2),
        isNot(DayOverride(date: date, capacity: 3)),
      );
    });

    test('capacity must not be negative', () {
      expect(() => DayOverride(date: date, capacity: -1), isAssertionError);
    });
  });
}
