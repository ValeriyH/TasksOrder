/// A calendar day without time or time zone.
///
/// Tasks are due on a calendar day, never on an instant, so the planner works
/// with [LocalDate] only (see docs/02 Architecture.md, "Dates"). Arithmetic
/// goes through UTC, which has no daylight saving switches, so a day is always
/// exactly 24 hours.
final class LocalDate implements Comparable<LocalDate> {
  /// Creates a date, throwing [ArgumentError] when it does not exist
  /// (for example 30 February) or the year is outside 1..9999.
  factory LocalDate(int year, int month, int day) {
    if (!_exists(year, month, day)) {
      throw ArgumentError('Not a calendar date: $year-$month-$day');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// The calendar date shown by [dateTime] in its own time zone; the time of
  /// day is dropped.
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  /// The planning day that [now] belongs to when days start at
  /// [dayStartHour] (0..23) instead of midnight (D15).
  ///
  /// With `dayStartHour = 4`, 03:59 still belongs to the previous calendar
  /// day and 04:00 starts the new one. Uses the calendar fields of [now] in
  /// its own time zone.
  factory LocalDate.todayFor(DateTime now, int dayStartHour) {
    RangeError.checkValueInInterval(dayStartHour, 0, 23, 'dayStartHour');
    final date = LocalDate.fromDateTime(now);
    return now.hour < dayStartHour ? date.addDays(-1) : date;
  }

  /// Parses a strict ISO 8601 calendar date (`yyyy-MM-dd`).
  ///
  /// Throws [FormatException] when [iso] has another shape or names a date
  /// that does not exist.
  factory LocalDate.parse(String iso) {
    final date = tryParse(iso);
    if (date == null) {
      throw FormatException('Expected a yyyy-MM-dd calendar date', iso);
    }
    return date;
  }

  /// Like [LocalDate.parse], but returns `null` instead of throwing.
  static LocalDate? tryParse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    return _exists(year, month, day) ? LocalDate._(year, month, day) : null;
  }

  // `[0-9]` and `(?![\s\S])` instead of `\d` and `$`: no other digits, and no
  // match before a trailing line break.
  static final _isoPattern = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})(?![\s\S])',
  );

  static const _msPerDay = Duration.millisecondsPerDay;

  final int year;

  /// 1..12.
  final int month;

  /// 1..31.
  final int day;

  /// Monday = 0 .. Sunday = 6, the index into `Settings.weeklyCapacity`.
  int get weekday => _utc.weekday - 1;

  /// The date [days] days after this one (before, when negative).
  LocalDate addDays(int days) {
    if (days == 0) return this;
    final utc = DateTime.fromMillisecondsSinceEpoch(
      (_epochDay + days) * _msPerDay,
      isUtc: true,
    );
    return LocalDate(utc.year, utc.month, utc.day);
  }

  /// Whole days from this date to [other]: positive when [other] is later,
  /// negative when it is earlier.
  int daysUntil(LocalDate other) => other._epochDay - _epochDay;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  /// ISO 8601 calendar date, `yyyy-MM-dd` (the storage format, ADR-3).
  String toIso() =>
      '${_pad(year, 4)}-'
      '${_pad(month, 2)}-'
      '${_pad(day, 2)}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();

  DateTime get _utc => DateTime.utc(year, month, day);

  /// Days since 1970-01-01. UTC midnights are exact multiples of a day, so
  /// the division has no remainder, also for dates before 1970.
  int get _epochDay => _utc.millisecondsSinceEpoch ~/ _msPerDay;

  static String _pad(int value, int width) =>
      value.toString().padLeft(width, '0');

  static bool _exists(int year, int month, int day) {
    if (year < 1 || year > 9999) return false;
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    // DateTime normalises overflow (30 Feb -> 2 Mar); a real date survives.
    final utc = DateTime.utc(year, month, day);
    return utc.year == year && utc.month == month && utc.day == day;
  }
}
