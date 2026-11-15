import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/backup/backup_codec.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/recurrence.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';

void main() {
  const codec = BackupCodec();
  final now = DateTime.utc(2026, 11, 13, 8, 30, 15, 250);

  Backup sample() {
    final plain = Task.create(
      id: 'plain',
      title: 'Plain',
      priority: 3,
      now: now,
    );
    final full =
        Task.create(
          id: 'full',
          title: 'Full',
          priority: 1,
          notes: 'line one\nline "two" і три',
          dueDate: LocalDate(2026, 11, 20),
          isFocused: true,
          now: now,
        ).copyWith(
          pinnedDate: LocalDate(2026, 11, 18),
          notBefore: LocalDate(2026, 11, 15),
        );
    final done = Task.create(id: 'done', title: 'Done', priority: 5, now: now)
        .complete(
          now.add(const Duration(hours: 1)),
          onPlan: true,
          plannedDate: LocalDate(2026, 11, 13),
        );
    final deleted = Task.create(
      id: 'deleted',
      title: 'Deleted',
      priority: 2,
      now: now,
    ).trash(now.add(const Duration(hours: 2)));
    return Backup(
      exportedAt: now,
      settings: Settings(
        priorityScale: 10,
        weeklyCapacity: const [2, 2, 2, 2, 2, 4, 0],
        maxOverflowPerDay: 2,
        planningHorizonDays: 30,
        urgencySoonDays: 5,
        urgencyNearDays: 1,
        focusVisibleLimit: 4,
        dayStartHour: 4,
      ),
      tasks: [plain, full, done, deleted],
      dayOverrides: [
        DayOverride(
          date: LocalDate(2026, 12, 25),
          capacity: 0,
          note: 'holiday',
        ),
        DayOverride(date: LocalDate(2026, 12, 26), capacity: 5),
      ],
    );
  }

  /// The sample as JSON, changed by [change], as text again.
  String changed(void Function(Map<String, dynamic> json) change) {
    final json = jsonDecode(codec.encode(sample())) as Map<String, dynamic>;
    change(json);
    return jsonEncode(json);
  }

  Map<String, dynamic> firstTask(Map<String, dynamic> json) =>
      (json['tasks'] as List<dynamic>).first as Map<String, dynamic>;

  Matcher fails(BackupProblem problem) => throwsA(
    isA<BackupFormatException>().having((e) => e.problem, 'problem', problem),
  );

  test('what is written is read back unchanged', () {
    final backup = sample();

    final read = codec.decode(codec.encode(backup));

    expect(read.exportedAt, backup.exportedAt);
    expect(read.settings, backup.settings);
    expect(read.tasks, backup.tasks);
    expect(read.dayOverrides, backup.dayOverrides);
  });

  test('the file names the app and the format version', () {
    final json = jsonDecode(codec.encode(sample())) as Map<String, dynamic>;

    expect(json['app'], 'TasksOrder');
    expect(json['version'], 4);
    expect(json['exportedAt'], '2026-11-13T08:30:15.250Z');
    expect(firstTask(json)['createdAt'], '2026-11-13T08:30:15.250Z');
  });

  test('taskCount leaves out the Trash', () {
    expect(sample().taskCount, 3);
  });

  test('an empty app gives a readable backup', () {
    final empty = Backup(
      exportedAt: now,
      settings: Settings(),
      tasks: const [],
      dayOverrides: const [],
    );

    final read = codec.decode(codec.encode(empty));

    expect(read.settings, Settings());
    expect(read.tasks, isEmpty);
    expect(read.dayOverrides, isEmpty);
  });

  group('not a backup', () {
    test('not JSON', () {
      expect(() => codec.decode('hello'), fails(BackupProblem.notABackup));
      expect(() => codec.decode(''), fails(BackupProblem.notABackup));
    });

    test('other JSON', () {
      expect(() => codec.decode('[1, 2]'), fails(BackupProblem.notABackup));
      expect(
        () => codec.decode('{"version": 1, "tasks": []}'),
        fails(BackupProblem.notABackup),
      );
    });

    test('a missing part', () {
      for (final part in ['settings', 'tasks', 'exportedAt', 'version']) {
        expect(
          () => codec.decode(changed((json) => json.remove(part))),
          fails(BackupProblem.notABackup),
          reason: part,
        );
      }
    });

    test('settings outside their limits', () {
      final cases = <String, Object>{
        'priorityScale': 4,
        'weeklyCapacity': [1, 1, 1],
        'maxOverflowPerDay': 9,
        'planningHorizonDays': 0,
        'urgencyNearDays': 30,
        'focusVisibleLimit': 0,
        'dayStartHour': 24,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(
          () => codec.decode(
            changed(
              (json) => (json['settings'] as Map<String, dynamic>)[key] = value,
            ),
          ),
          fails(BackupProblem.notABackup),
          reason: key,
        );
      }
    });

    test('a task that breaks the rules', () {
      final cases = <String, void Function(Map<String, dynamic> task)>{
        'blank title': (task) => task['title'] = '  ',
        'unknown status': (task) => task['status'] = 'dropped',
        'done without a time': (task) => task['status'] = 'done',
        'focused without a time': (task) => task['isFocused'] = true,
        'on plan but active': (task) => task['completedOnPlan'] = true,
        'bad date': (task) => task['dueDate'] = '2026-02-30',
        'no id': (task) => task.remove('id'),
      };
      for (final MapEntry(key: name, value: change) in cases.entries) {
        expect(
          () => codec.decode(changed((json) => change(firstTask(json)))),
          fails(BackupProblem.notABackup),
          reason: name,
        );
      }
    });

    test('the same id twice', () {
      expect(
        () => codec.decode(
          changed((json) {
            final tasks = json['tasks'] as List<dynamic>;
            tasks.add(tasks.first);
          }),
        ),
        fails(BackupProblem.notABackup),
      );
    });
  });

  test('a backup of a newer format is told apart', () {
    expect(
      () => codec.decode(changed((json) => json['version'] = 5)),
      fails(BackupProblem.newerVersion),
    );
  });

  group('the plan day of a completion (format 4, T-907)', () {
    Map<String, dynamic> task(Map<String, dynamic> json, String id) =>
        (json['tasks'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .singleWhere((task) => task['id'] == id);

    test('is written for a done task only', () {
      final json = jsonDecode(codec.encode(sample())) as Map<String, dynamic>;

      expect(task(json, 'done')['completedPlanDate'], '2026-11-13');
      expect(task(json, 'plain').containsKey('completedPlanDate'), isFalse);
    });

    test('a file of version 3 has none', () {
      final read = codec.decode(
        changed((json) {
          json['version'] = 3;
          task(json, 'done').remove('completedPlanDate');
        }),
      );

      final done = read.tasks.singleWhere((t) => t.id == 'done');
      expect(done.completedPlanDate, isNull);
      expect(done.completedOnPlan, isTrue);
    });

    test('on an active task it is refused', () {
      expect(
        () => codec.decode(
          changed(
            (json) => task(json, 'plain')['completedPlanDate'] = '2026-11-13',
          ),
        ),
        fails(BackupProblem.notABackup),
      );
    });
  });

  test('a priority outside 1..10 moves to its nearest end', () {
    final read = codec.decode(
      changed((json) {
        final tasks = json['tasks'] as List<dynamic>;
        (tasks[0] as Map<String, dynamic>)['priority'] = 0;
        (tasks[2] as Map<String, dynamic>)['priority'] = 12;
      }),
    );

    expect(read.tasks.map((task) => task.priority), [1, 1, 10, 2]);
  });

  test('the scale does not change the priorities (ADR-17)', () {
    final read = codec.decode(
      changed((json) {
        (json['settings'] as Map<String, dynamic>)['priorityScale'] = 3;
      }),
    );

    expect(read.tasks.map((task) => task.priority), [3, 1, 5, 2]);
  });

  group('format 1: a priority was the position in the scale', () {
    String version1({required int scale, required List<int> priorities}) =>
        changed((json) {
          json['version'] = 1;
          (json['settings'] as Map<String, dynamic>)['priorityScale'] = scale;
          final tasks = json['tasks'] as List<dynamic>;
          for (var i = 0; i < tasks.length; i++) {
            (tasks[i] as Map<String, dynamic>)['priority'] = priorities[i];
          }
        });

    test('scale 5: Critical, High, Normal, Low, Someday keep their names', () {
      final read = codec.decode(version1(scale: 5, priorities: [1, 2, 3, 5]));

      expect(read.tasks.map((task) => task.priority), [2, 3, 5, 8]);
    });

    test('scale 3: Critical, Normal, Low; past the end is Low', () {
      final read = codec.decode(version1(scale: 3, priorities: [1, 2, 3, 9]));

      expect(read.tasks.map((task) => task.priority), [2, 5, 7, 7]);
    });

    test('scale 10 is already the table', () {
      final read = codec.decode(version1(scale: 10, priorities: [1, 4, 9, 10]));

      expect(read.tasks.map((task) => task.priority), [1, 4, 9, 10]);
    });
  });

  test('unknown fields are ignored', () {
    final read = codec.decode(
      changed((json) {
        json['later'] = {'a': 1};
        firstTask(json)['colour'] = 'red';
      }),
    );

    expect(read.tasks, sample().tasks);
  });

  group('format 3: repeat rules (D20, T-706)', () {
    final today = LocalDate(2026, 11, 13);
    final rules = [
      Recurrence.interval(every: 1, unit: RecurrenceUnit.month, anchor: today),
      Recurrence.interval(every: 2, unit: RecurrenceUnit.week, anchor: today),
      Recurrence.interval(every: 1, unit: RecurrenceUnit.year, anchor: today),
      Recurrence.interval(every: 10, unit: RecurrenceUnit.day, afterDone: true),
      Recurrence.weekdays(const {0, 2, 4}),
    ];

    Backup withSeries() {
      final base = sample();
      return Backup(
        exportedAt: base.exportedAt,
        settings: base.settings,
        dayOverrides: base.dayOverrides,
        tasks: [
          ...base.tasks,
          for (final (i, rule) in rules.indexed)
            Task.create(
              id: 'r$i',
              title: 'Repeat $i',
              priority: 5,
              dueDate: today,
              now: now,
            ).setRecurrence(rule, today: today, now: now),
        ],
      );
    }

    /// The JSON of [withSeries], changed by [change], as text again.
    String changedSeries(void Function(List<dynamic> tasks) change) {
      final json =
          jsonDecode(codec.encode(withSeries())) as Map<String, dynamic>;
      change(json['tasks'] as List<dynamic>);
      return jsonEncode(json);
    }

    Map<String, dynamic> series(List<dynamic> tasks, String id) =>
        tasks.cast<Map<String, dynamic>>().singleWhere((t) => t['id'] == id);

    test('every kind of rule is read back', () {
      final backup = withSeries();

      final read = codec.decode(codec.encode(backup));

      expect(read.tasks, backup.tasks);
      expect([for (final t in read.tasks) ?t.recurrence], rules);
    });

    test('an ordinary task carries none of the three fields', () {
      final json = jsonDecode(codec.encode(sample())) as Map<String, dynamic>;

      expect(firstTask(json).containsKey('recurrence'), isFalse);
      expect(firstTask(json).containsKey('seriesId'), isFalse);
      expect(firstTask(json).containsKey('occurrenceDate'), isFalse);
    });

    test('a file of version 2 is read as before', () {
      final read = codec.decode(changed((json) => json['version'] = 2));

      expect(read.tasks, sample().tasks);
    });

    test('a broken rule is refused', () {
      expect(
        () => codec.decode(
          changedSeries((tasks) {
            series(tasks, 'r0')['recurrence'] = {
              'kind': 'interval',
              'every': 0,
              'unit': 'month',
              'afterDone': false,
              'anchor': '2026-11-13',
            };
          }),
        ),
        fails(BackupProblem.notABackup),
      );
    });

    test('a rule without seriesId or occurrenceDate is refused', () {
      for (final field in ['seriesId', 'occurrenceDate']) {
        expect(
          () => codec.decode(
            changedSeries((tasks) => series(tasks, 'r1').remove(field)),
          ),
          fails(BackupProblem.notABackup),
          reason: field,
        );
      }
    });

    test('two active instances of one series are refused', () {
      expect(
        () => codec.decode(
          changedSeries((tasks) => series(tasks, 'r2')['seriesId'] = 'r1'),
        ),
        fails(BackupProblem.notABackup),
      );
    });

    test('a done or deleted instance next to the active one is fine', () {
      final read = codec.decode(
        changedSeries((tasks) {
          final done = Map<String, dynamic>.of(series(tasks, 'r1'))
            ..['id'] = 'r1-done'
            ..['status'] = 'done'
            ..['completedAt'] = '2026-11-13T09:00:00.000Z';
          final deleted = Map<String, dynamic>.of(series(tasks, 'r1'))
            ..['id'] = 'r1-deleted'
            ..['deletedAt'] = '2026-11-13T09:00:00.000Z';
          tasks
            ..add(done)
            ..add(deleted);
        }),
      );

      expect(read.tasks.where((t) => t.seriesId == 'r1'), hasLength(3));
    });
  });
}
