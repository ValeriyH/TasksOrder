import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/task.dart';

/// T-702: the fields of a series and its transitions (D20, ADR-18; the
/// date table of docs/03 Data Model.md).
void main() {
  LocalDate d(int y, int m, int day) => LocalDate(y, m, day);
  final created = DateTime.utc(2026, 11, 1, 9);
  final now = DateTime.utc(2026, 11, 15, 12);
  final today = d(2026, 11, 15);

  Task task({LocalDate? due, LocalDate? pin, LocalDate? notBefore}) =>
      Task.create(
        id: 'a1',
        title: 'Pay rent',
        notes: 'bank',
        priority: PriorityLabels.normal,
        dueDate: due,
        isFocused: true,
        now: created,
      ).copyWith(pinnedDate: pin, notBefore: notBefore);

  final monthly = Recurrence.interval(
    every: 1,
    unit: RecurrenceUnit.month,
    // Replaced by the occurrence date when the rule is set.
    anchor: d(2000, 1, 1),
  );
  final every10DaysAfterDone = Recurrence.interval(
    every: 10,
    unit: RecurrenceUnit.day,
    afterDone: true,
  );

  group('setRecurrence (Start)', () {
    test('starts a series: own id, occurrence date, anchor', () {
      final t = task(due: d(2026, 11, 30))
          .setRecurrence(monthly, today: today, now: now);

      expect(t.seriesId, 'a1');
      expect(t.occurrenceDate, d(2026, 11, 30));
      expect(
        t.recurrence,
        Recurrence.interval(
          every: 1,
          unit: RecurrenceUnit.month,
          anchor: d(2026, 11, 30),
        ),
      );
      expect(t.updatedAt, now);
    });

    test(
      'the occurrence date is pin, else due, else not before, else today',
      () {
        LocalDate? occurrence(Task t) => t
            .setRecurrence(every10DaysAfterDone, today: today, now: now)
            .occurrenceDate;

        expect(
          occurrence(task(pin: d(2026, 11, 20), due: d(2026, 11, 25))),
          d(2026, 11, 20),
        );
        expect(occurrence(task(due: d(2026, 11, 25))), d(2026, 11, 25));
        expect(occurrence(task(notBefore: d(2026, 11, 18))), d(2026, 11, 18));
        expect(occurrence(task()), today);
      },
    );

    test('a rule from completion keeps no anchor', () {
      final t = task().setRecurrence(
        every10DaysAfterDone,
        today: today,
        now: now,
      );

      expect(t.recurrence, every10DaysAfterDone);
    });

    test('setting it again moves the anchor, keeps the series', () {
      final first = task(due: d(2026, 11, 30))
          .setRecurrence(monthly, today: today, now: now);
      final moved = first
          .copyWith(seriesId: 'series', dueDate: d(2026, 12, 5))
          .setRecurrence(monthly, today: today, now: now);

      expect(moved.seriesId, 'series');
      expect(moved.occurrenceDate, d(2026, 12, 5));
      expect((moved.recurrence! as IntervalRecurrence).anchor, d(2026, 12, 5));
    });
  });

  test('clearRecurrence leaves an ordinary task of the series', () {
    final t = task()
        .setRecurrence(monthly, today: today, now: now)
        .clearRecurrence(now.add(const Duration(hours: 1)));

    expect(t.recurrence, isNull);
    expect(t.occurrenceDate, isNull);
    expect(t.seriesId, 'a1');
    expect(t.updatedAt, now.add(const Duration(hours: 1)));
  });

  test('a rule without series and occurrence date is refused', () {
    expect(
      () => task().copyWith(recurrence: every10DaysAfterDone),
      throwsA(isA<AssertionError>()),
    );
  });

  group('successor', () {
    final doneAt = DateTime.utc(2026, 11, 15, 18);

    Task recurring(
      Recurrence rule, {
      LocalDate? due,
      LocalDate? pin,
      LocalDate? notBefore,
    }) => task(
      due: due,
      pin: pin,
      notBefore: notBefore,
    ).setRecurrence(rule, today: today, now: now);

    test('copies the task, gets a fresh active instance without Focus', () {
      final t = recurring(monthly, due: d(2026, 11, 15));
      final next = t.successor(now: doneAt, today: today);

      expect(next.id, t.successorId);
      expect(next.title, 'Pay rent');
      expect(next.notes, 'bank');
      expect(next.priority, t.priority);
      expect(next.recurrence, t.recurrence);
      expect(next.seriesId, 'a1');
      expect(next.isDone, isFalse);
      expect(next.isFocused, isFalse);
      expect(next.focusedAt, isNull);
      expect(next.createdAt, doneAt);
      expect(next.updatedAt, doneAt);
      expect(next.isDeleted, isFalse);
    });

    test('carries the weight of the series (D21)', () {
      for (final weight in [1, 3, 4]) {
        final t = recurring(monthly).copyWith(weight: weight);
        expect(t.successor(now: doneAt, today: today).weight, weight);
      }
    });

    test('carries the allowed days of the series (D23)', () {
      for (final rule in [monthly, every10DaysAfterDone]) {
        final t = recurring(rule).setAllowedWeekdays({5}, now);
        expect(t.successor(now: doneAt, today: today).allowedWeekdays, {5});
        expect(
          t.successor(now: doneAt, today: today, skipped: true).allowedWeekdays,
          {5},
        );
      }
      expect(
        recurring(monthly).successor(now: doneAt, today: today).allowedWeekdays,
        isNull,
      );
    });

    test('the successor id is the same on every call and every device', () {
      final t = recurring(monthly);

      expect(t.successorId, t.successorId);
      expect(t.successor(now: doneAt, today: today).id, t.successorId);
      expect(t.successorId, isNot(t.id));
      expect(
        t.successorId,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-')),
      );
      expect(t.copyWith(id: 'other').successorId, isNot(t.successorId));
    });

    test('a task without a rule has no successor', () {
      expect(
        () => task().successor(now: doneAt, today: today),
        throwsStateError,
      );
    });

    group('date table', () {
      test('pinned: the pin moves, a due date keeps its distance', () {
        final t = recurring(
          monthly,
          pin: d(2026, 11, 15),
          due: d(2026, 11, 18),
        );
        final next = t.successor(now: doneAt, today: today);

        expect(next.occurrenceDate, d(2026, 12, 15));
        expect(next.pinnedDate, d(2026, 12, 15));
        expect(next.dueDate, d(2026, 12, 18));
        expect(next.notBefore, isNull);
      });

      test('pinned without a due date', () {
        final next = recurring(
          monthly,
          pin: d(2026, 11, 15),
        ).successor(now: doneAt, today: today);

        expect(next.pinnedDate, d(2026, 12, 15));
        expect(next.dueDate, isNull);
      });

      test('due only: due on the next date, free from the day after', () {
        final next = recurring(
          monthly,
          due: d(2026, 11, 15),
        ).successor(now: doneAt, today: today);

        expect(next.occurrenceDate, d(2026, 12, 15));
        expect(next.dueDate, d(2026, 12, 15));
        expect(next.notBefore, d(2026, 11, 16));
        expect(next.pinnedDate, isNull);
      });

      test('neither: available from the next date', () {
        final next = recurring(monthly).successor(now: doneAt, today: today);

        expect(next.occurrenceDate, d(2026, 12, 15));
        expect(next.notBefore, d(2026, 12, 15));
        expect(next.dueDate, isNull);
        expect(next.pinnedDate, isNull);
      });
    });

    group('by schedule', () {
      test('a late completion drops the missed repeats', () {
        // Occurrence Nov 15, done on Jan 20: next is Feb 15, not Dec 15.
        final next = recurring(
          monthly,
          due: d(2026, 11, 15),
        ).successor(now: doneAt, today: d(2027, 1, 20));

        expect(next.occurrenceDate, d(2027, 2, 15));
      });

      test('an early completion does not give a second one for the date', () {
        // Occurrence Dec 15, done on Nov 20: next is Jan 15.
        final t = recurring(monthly, due: d(2026, 12, 15));
        final next = t.successor(now: doneAt, today: d(2026, 11, 20));

        expect(t.occurrenceDate, d(2026, 12, 15));
        expect(next.occurrenceDate, d(2027, 1, 15));
        expect(next.notBefore, d(2026, 12, 16));
      });

      test('weekdays', () {
        // Mon, Thu; occurrence Sunday Nov 15 (today).
        final next = recurring(Recurrence.weekdays(const {0, 3}))
            .successor(now: doneAt, today: today);

        expect(next.occurrenceDate, d(2026, 11, 16));
      });
    });

    group('from completion (T-712)', () {
      // Haircut every 10 days, available from Nov 25.
      final haircut = recurring(
        every10DaysAfterDone,
        notBefore: d(2026, 11, 25),
      );

      test('a completion counts from the day it is done, early, on the day '
          'or late', () {
        for (final (done, next) in [
          (d(2026, 11, 15), d(2026, 11, 25)),
          (d(2026, 11, 25), d(2026, 12, 5)),
          (d(2026, 11, 27), d(2026, 12, 7)),
        ]) {
          final s = haircut.successor(now: doneAt, today: done);
          expect(s.occurrenceDate, next, reason: '$done');
          expect(s.notBefore, next, reason: '$done');
          expect(s.pinnedDate, isNull);
          expect(s.dueDate, isNull);
        }
      });

      test(
        'a skip counts from the later of today and the instance\'s date',
        () {
          for (final (skipped, next) in [
            // Ahead: "not this time" means not on the 25th.
            (d(2026, 11, 15), d(2026, 12, 5)),
            (d(2026, 11, 25), d(2026, 12, 5)),
            // Late: from today, so the next one is never in the past.
            (d(2026, 11, 27), d(2026, 12, 7)),
          ]) {
            final s = haircut.successor(
              now: doneAt,
              today: skipped,
              skipped: true,
            );
            expect(s.occurrenceDate, next, reason: '$skipped');
            expect(s.notBefore, next, reason: '$skipped');
          }
        },
      );

      test('a pinned instance gives a pinned successor; a skip counts from '
          'the pin', () {
        final pinned = recurring(every10DaysAfterDone, pin: d(2026, 11, 25));

        final done = pinned.successor(now: doneAt, today: d(2026, 11, 20));
        expect(done.pinnedDate, d(2026, 11, 30));
        expect(done.notBefore, isNull);

        final skip = pinned.successor(
          now: doneAt,
          today: d(2026, 11, 20),
          skipped: true,
        );
        expect(skip.pinnedDate, d(2026, 12, 5));
        expect(skip.occurrenceDate, d(2026, 12, 5));
      });

      test('a due date is not carried over', () {
        final t = recurring(
          every10DaysAfterDone,
          pin: d(2026, 11, 15),
          due: d(2026, 11, 18),
        );
        expect(t.successor(now: doneAt, today: today).dueDate, isNull);

        final dueOnly = recurring(
          every10DaysAfterDone,
          due: d(2026, 11, 15),
        ).successor(now: doneAt, today: d(2026, 11, 20));
        expect(dueOnly.dueDate, isNull);
        expect(dueOnly.notBefore, d(2026, 11, 30));
      });
    });

    test('a skip by schedule is the same as a completion', () {
      final t = recurring(monthly, due: d(2026, 12, 15));
      final today = d(2026, 11, 20);

      expect(
        t.successor(now: doneAt, today: today, skipped: true),
        t.successor(now: doneAt, today: today),
      );
    });
  });
}
