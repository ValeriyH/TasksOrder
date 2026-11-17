import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';

/// Calendar day as ISO `yyyy-MM-dd` text (ADR-3). The text form sorts like the
/// date, so SQL can compare and order it.
class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parse(fromDb);

  @override
  String toSql(LocalDate value) => value.toIso();
}

/// Instant as UTC epoch milliseconds (ADR-3).
///
/// Anything below a millisecond is dropped on the way in, so a value read
/// back equals the written one only at millisecond precision.
class UtcMillisConverter extends TypeConverter<DateTime, int> {
  const UtcMillisConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// List of ints as a JSON array, e.g. `[1,1,1,1,1,3,0]` for the weekly
/// capacity.
class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) =>
      List<int>.unmodifiable((jsonDecode(fromDb) as List<dynamic>).cast<int>());

  @override
  String toSql(List<int> value) => jsonEncode(value);
}

/// The allowed weekdays of a task (D23) as a JSON array in ascending order,
/// e.g. `[3,4]` for Thursday and Friday (Monday = 0). The same array is in
/// the backup.
class WeekdaySetConverter extends TypeConverter<Set<int>, String> {
  const WeekdaySetConverter();

  @override
  Set<int> fromSql(String fromDb) =>
      fromJson(jsonDecode(fromDb) as List<dynamic>);

  @override
  String toSql(Set<int> value) => jsonEncode(toJson(value));

  /// The JSON array of [days], sorted.
  static List<int> toJson(Set<int> days) => days.toList()..sort();

  /// The set in [json]. Throws [FormatException] for an empty array, a value
  /// that is not a weekday 0..6 or a repeated one.
  static Set<int> fromJson(List<dynamic> json) {
    final days = <int>{};
    for (final item in json) {
      if (item is! int || item < 0 || item > 6 || !days.add(item)) {
        throw FormatException('Not a set of weekdays', json);
      }
    }
    if (days.isEmpty) throw FormatException('No weekdays', json);
    return days;
  }
}

/// A repeat rule as JSON text (D20), the same in the database column and in
/// the backup (docs/03 Data Model.md, "Recurrence"):
///
///     {"kind":"interval","every":1,"unit":"month","afterDone":false,"anchor":"2026-11-30"}
///     {"kind":"interval","every":30,"unit":"day","afterDone":true}
///     {"kind":"weekdays","days":[0,2,4]}
class RecurrenceConverter extends TypeConverter<Recurrence, String> {
  const RecurrenceConverter();

  @override
  Recurrence fromSql(String fromDb) =>
      fromJson(jsonDecode(fromDb) as Map<String, dynamic>);

  @override
  String toSql(Recurrence value) => jsonEncode(toJson(value));

  /// The JSON object of [rule].
  static Map<String, Object> toJson(Recurrence rule) => switch (rule) {
    IntervalRecurrence(
      :final every,
      :final unit,
      :final afterDone,
      :final anchor,
    ) =>
      {
        'kind': 'interval',
        'every': every,
        'unit': unit.name,
        'afterDone': afterDone,
        'anchor': ?anchor?.toIso(),
      },
    WeekdaysRecurrence(:final days) => {
      'kind': 'weekdays',
      'days': days.toList()..sort(),
    },
  };

  /// The rule in [json]. Throws [FormatException] when it is not a valid
  /// rule: an unknown kind or unit, a wrong type, or values the domain
  /// refuses (`every < 1`, an anchor where there must be none, weekdays
  /// outside 0..6).
  static Recurrence fromJson(Map<String, dynamic> json) {
    try {
      switch (json['kind']) {
        case 'interval':
          final unitName = json['unit'] as String;
          final unit = RecurrenceUnit.values.where((u) => u.name == unitName);
          if (unit.isEmpty) throw FormatException('Unknown unit', unitName);
          final anchor = json['anchor'] as String?;
          return Recurrence.interval(
            every: json['every'] as int,
            unit: unit.single,
            afterDone: json['afterDone'] as bool,
            anchor: anchor == null ? null : LocalDate.parse(anchor),
          );
        case 'weekdays':
          return Recurrence.weekdays({
            for (final day in json['days'] as List<dynamic>) day as int,
          });
        default:
          throw FormatException('Unknown kind of repeat rule', json['kind']);
      }
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      // A wrong type (TypeError) or a rule the domain refuses (ArgumentError).
      throw FormatException('Not a repeat rule: $e', json);
    }
  }
}
