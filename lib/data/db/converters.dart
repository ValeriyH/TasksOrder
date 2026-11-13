import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tasks_order/domain/model/local_date.dart';

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
