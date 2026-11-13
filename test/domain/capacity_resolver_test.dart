import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';

void main() {
  // 2026-11-16 is a Monday.
  final monday = LocalDate(2026, 11, 16);

  Map<LocalDate, DayOverride> byDate(List<DayOverride> overrides) => {
    for (final o in overrides) o.date: o,
  };

  group('CapacityResolver.capacityFor', () {
    test('uses the weekday capacity, Monday first', () {
      final resolver = CapacityResolver(
        Settings(weeklyCapacity: [1, 2, 3, 4, 5, 6, 0]),
      );
      expect(
        [for (var i = 0; i < 7; i++) resolver.capacityFor(monday.addDays(i))],
        [1, 2, 3, 4, 5, 6, 0],
      );
    });

    test('repeats every week', () {
      final resolver = CapacityResolver(Settings());
      expect(resolver.capacityFor(monday.addDays(5)), 3); // Saturday
      expect(resolver.capacityFor(monday.addDays(12)), 3); // next Saturday
      expect(resolver.capacityFor(monday.addDays(6)), 0); // Sunday
      expect(resolver.capacityFor(monday.addDays(13)), 0);
    });

    test('an override wins over the weekday', () {
      final resolver = CapacityResolver(
        Settings(),
        byDate([DayOverride(date: monday, capacity: 4)]),
      );
      expect(resolver.capacityFor(monday), 4);
    });

    test('an override applies to its date only', () {
      final resolver = CapacityResolver(
        Settings(),
        byDate([DayOverride(date: monday, capacity: 4)]),
      );
      expect(resolver.capacityFor(monday.addDays(1)), 1);
      expect(resolver.capacityFor(monday.addDays(7)), 1); // next Monday
      expect(resolver.capacityFor(monday.addDays(-7)), 1);
    });

    test('an override of 0 turns a working day into a rest day', () {
      final resolver = CapacityResolver(
        Settings(),
        byDate([DayOverride(date: monday, capacity: 0, note: 'sick')]),
      );
      expect(resolver.capacityFor(monday), 0);
    });

    test('an override can open a rest day', () {
      final sunday = monday.addDays(6);
      final resolver = CapacityResolver(
        Settings(),
        byDate([DayOverride(date: sunday, capacity: 2)]),
      );
      expect(resolver.capacityFor(sunday), 2);
    });

    test('several overrides are independent', () {
      final resolver = CapacityResolver(
        Settings(),
        byDate([
          DayOverride(date: monday, capacity: 5),
          DayOverride(date: monday.addDays(2), capacity: 0),
        ]),
      );
      expect(resolver.capacityFor(monday), 5);
      expect(resolver.capacityFor(monday.addDays(1)), 1);
      expect(resolver.capacityFor(monday.addDays(2)), 0);
    });
  });
}
