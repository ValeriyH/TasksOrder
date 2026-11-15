import 'package:tasks_order/domain/model/local_date.dart';

/// The unit of an interval rule.
enum RecurrenceUnit { day, week, month, year }

/// How a task repeats (D20, ADR-18). Two kinds: [IntervalRecurrence] (every
/// N units, by schedule or from completion) and [WeekdaysRecurrence].
///
/// A plain sealed class rather than a `freezed` one: the factories check
/// the rule at run time, also in a release build, where assertions are off.
/// Rules are compared by value.
sealed class Recurrence {
  const Recurrence._();

  /// Every [every] [unit]s. By schedule ([afterDone] false) the dates are
  /// `anchor + k × every` units, each computed from [anchor]; from completion
  /// ([afterDone] true) the next date is the day of completion + [every]
  /// units, and there is no anchor.
  ///
  /// Throws [ArgumentError] when [every] is below 1 or [anchor] is given
  /// when it must not be, or missing when it must be.
  factory Recurrence.interval({
    required int every,
    required RecurrenceUnit unit,
    bool afterDone = false,
    LocalDate? anchor,
  }) {
    if (every < 1) {
      throw ArgumentError.value(every, 'every', 'must be at least 1');
    }
    if (afterDone && anchor != null) {
      throw ArgumentError.value(
        anchor,
        'anchor',
        'a rule from completion has no anchor',
      );
    }
    if (!afterDone && anchor == null) {
      throw ArgumentError.notNull('anchor');
    }
    return IntervalRecurrence._(every, unit, afterDone, anchor);
  }

  /// Every listed weekday, Monday = 0 .. Sunday = 6 as in
  /// [LocalDate.weekday]; always by schedule.
  ///
  /// Throws [ArgumentError] when [days] is empty or holds a value outside
  /// 0..6.
  factory Recurrence.weekdays(Set<int> days) {
    if (days.isEmpty) {
      throw ArgumentError.value(days, 'days', 'must not be empty');
    }
    for (final day in days) {
      if (day < 0 || day > 6) {
        throw ArgumentError.value(days, 'days', 'must be within 0..6');
      }
    }
    return WeekdaysRecurrence._(Set.unmodifiable(days));
  }

  /// The next date counts from the day the task was done.
  bool get isAfterDone;

  /// The first date of the rule after [date] (not [date] itself).
  ///
  /// For a rule from completion it is the date after a completion on
  /// [date], [addTo].
  LocalDate firstAfter(LocalDate date);

  /// For a rule from completion: the next date when the task is done on
  /// [date]. Throws [StateError] for a rule by schedule.
  LocalDate addTo(LocalDate date);

  /// The dates of the rule after [base], up to and including [until]: the
  /// coming repeats of the horizon (ghosts, T-704). For a rule from
  /// completion they are a forecast that assumes each one is done on its
  /// day.
  Iterable<LocalDate> datesAfter(LocalDate base, LocalDate until) sync* {
    var next = firstAfter(base);
    while (next <= until) {
      yield next;
      next = firstAfter(next);
    }
  }
}

/// Every [every] [unit]s; see [Recurrence.interval].
final class IntervalRecurrence extends Recurrence {
  const IntervalRecurrence._(this.every, this.unit, this.afterDone, this.anchor)
    : super._();

  final int every;
  final RecurrenceUnit unit;
  final bool afterDone;

  /// The first date of a rule by schedule; null for one from completion.
  final LocalDate? anchor;

  @override
  bool get isAfterDone => afterDone;

  @override
  LocalDate addTo(LocalDate date) {
    if (!afterDone) {
      throw StateError('A rule by schedule does not count from completion');
    }
    return _shift(date, every);
  }

  @override
  LocalDate firstAfter(LocalDate date) {
    final anchor = this.anchor;
    if (anchor == null) return addTo(date);
    if (anchor > date) return anchor;
    // Start a step below the estimate and walk up: months and years are not
    // of equal length, so the estimate may be one off.
    var k = _unitsBetween(anchor, date) ~/ every - 1;
    if (k < 0) k = 0;
    while (true) {
      final candidate = _shift(anchor, k * every);
      if (candidate > date) return candidate;
      k++;
    }
  }

  LocalDate _shift(LocalDate date, int units) => switch (unit) {
    RecurrenceUnit.day => date.addDays(units),
    RecurrenceUnit.week => date.addDays(units * 7),
    RecurrenceUnit.month => date.addMonths(units),
    RecurrenceUnit.year => date.addYears(units),
  };

  /// Whole units from [from] to [to], rounded down; an estimate for months
  /// and years.
  int _unitsBetween(LocalDate from, LocalDate to) => switch (unit) {
    RecurrenceUnit.day => from.daysUntil(to),
    RecurrenceUnit.week => from.daysUntil(to) ~/ 7,
    RecurrenceUnit.month => (to.year - from.year) * 12 + to.month - from.month,
    RecurrenceUnit.year => to.year - from.year,
  };

  @override
  bool operator ==(Object other) =>
      other is IntervalRecurrence &&
      other.every == every &&
      other.unit == unit &&
      other.afterDone == afterDone &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(every, unit, afterDone, anchor);

  @override
  String toString() =>
      'Recurrence.interval(every: $every, unit: ${unit.name}, '
      '${afterDone ? 'afterDone' : 'anchor: $anchor'})';
}

/// Every listed weekday; see [Recurrence.weekdays].
final class WeekdaysRecurrence extends Recurrence {
  const WeekdaysRecurrence._(this.days) : super._();

  /// Monday = 0 .. Sunday = 6; never empty.
  final Set<int> days;

  @override
  bool get isAfterDone => false;

  @override
  LocalDate addTo(LocalDate date) =>
      throw StateError('A weekday rule does not count from completion');

  @override
  LocalDate firstAfter(LocalDate date) {
    for (var offset = 1; offset <= 7; offset++) {
      final candidate = date.addDays(offset);
      if (days.contains(candidate.weekday)) return candidate;
    }
    throw StateError('unreachable: days is never empty');
  }

  @override
  bool operator ==(Object other) =>
      other is WeekdaysRecurrence &&
      other.days.length == days.length &&
      other.days.containsAll(days);

  @override
  int get hashCode => Object.hashAllUnordered(days);

  @override
  String toString() => 'Recurrence.weekdays(${days.toList()..sort()})';
}
