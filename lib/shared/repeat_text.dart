import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/l10n/l10n.dart';

/// One line about a repeat rule (D20): "Every 2 weeks", "Mon, Wed, Fri",
/// "30 days after it is done".
String repeatSummary(AppLocalizations l10n, Recurrence rule) => switch (rule) {
  IntervalRecurrence(:final every, :final unit, afterDone: true) =>
    l10n.repeatAfterDoneSummary(unitCount(l10n, unit, every)),
  IntervalRecurrence(:final every, :final unit) => switch (unit) {
    RecurrenceUnit.day =>
      every == 1 ? l10n.repeatDaily : l10n.repeatEveryDay(every),
    RecurrenceUnit.week =>
      every == 1 ? l10n.repeatWeekly : l10n.repeatEveryWeek(every),
    RecurrenceUnit.month =>
      every == 1 ? l10n.repeatMonthly : l10n.repeatEveryMonth(every),
    RecurrenceUnit.year =>
      every == 1 ? l10n.repeatYearly : l10n.repeatEveryYear(every),
  },
  WeekdaysRecurrence(:final days) => [
    for (var day = 0; day < 7; day++)
      if (days.contains(day)) shortWeekday(l10n, day),
  ].join(', '),
};

/// "3 days", "1 week", "2 months".
String unitCount(AppLocalizations l10n, RecurrenceUnit unit, int count) =>
    switch (unit) {
      RecurrenceUnit.day => l10n.daysCount(count),
      RecurrenceUnit.week => l10n.weeksCount(count),
      RecurrenceUnit.month => l10n.monthsCount(count),
      RecurrenceUnit.year => l10n.yearsCount(count),
    };

/// The unit word after a number: "day" / "days".
String unitName(AppLocalizations l10n, RecurrenceUnit unit, int count) =>
    switch (unit) {
      RecurrenceUnit.day => l10n.unitDays(count),
      RecurrenceUnit.week => l10n.unitWeeks(count),
      RecurrenceUnit.month => l10n.unitMonths(count),
      RecurrenceUnit.year => l10n.unitYears(count),
    };

/// Monday = 0 .. Sunday = 6, as in `LocalDate.weekday`.
String shortWeekday(AppLocalizations l10n, int day) => switch (day) {
  0 => l10n.weekdayShortMon,
  1 => l10n.weekdayShortTue,
  2 => l10n.weekdayShortWed,
  3 => l10n.weekdayShortThu,
  4 => l10n.weekdayShortFri,
  5 => l10n.weekdayShortSat,
  _ => l10n.weekdayShortSun,
};
