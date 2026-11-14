import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/data/backup/backup_codec.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
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
    final done = Task.create(
      id: 'done',
      title: 'Done',
      priority: 5,
      now: now,
    ).complete(now.add(const Duration(hours: 1)), onPlan: true);
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
    expect(json['version'], 2);
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
      () => codec.decode(changed((json) => json['version'] = 3)),
      fails(BackupProblem.newerVersion),
    );
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
}
