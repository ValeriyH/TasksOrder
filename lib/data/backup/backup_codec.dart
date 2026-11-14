import 'dart:convert';

import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';

/// The backup file: one JSON document, see "Backup format" in
/// docs/03 Data Model.md. Hand-written mappers (ADR-8).
///
/// Instants are ISO-8601 UTC text, calendar days `yyyy-MM-dd`.
class BackupCodec {
  const BackupCodec();

  /// Value of the `app` field: tells our files from any other JSON.
  static const appName = 'TasksOrder';

  /// Format version this app writes, and the highest one it reads.
  static const version = 1;

  String encode(Backup backup) => const JsonEncoder.withIndent('  ').convert({
    'app': appName,
    'version': version,
    'exportedAt': _instant(backup.exportedAt),
    'settings': _settings(backup.settings),
    'tasks': [for (final task in backup.tasks) _task(task)],
    'dayOverrides': [
      for (final override in backup.dayOverrides)
        {
          'date': override.date.toIso(),
          'capacity': override.capacity,
          'note': ?override.note,
        },
    ],
  });

  /// Reads a backup file. Throws [BackupFormatException] when [text] is not
  /// one, is damaged, or comes from a newer version of the app.
  ///
  /// The rules of the domain objects are checked here and not left to their
  /// assertions, which a release build does not run. A priority outside the
  /// scale of the backup is moved to its nearest end.
  Backup decode(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      _require(json['app'] == appName);
      final fileVersion = json['version'] as int;
      _require(fileVersion >= 1);
      if (fileVersion > version) {
        throw const BackupFormatException(BackupProblem.newerVersion);
      }

      final settings = _readSettings(json['settings'] as Map<String, dynamic>);
      final tasks = [
        for (final task in json['tasks'] as List<dynamic>)
          _readTask(task as Map<String, dynamic>, settings.priorityScale),
      ];
      _require({for (final task in tasks) task.id}.length == tasks.length);
      final overrides = [
        for (final item in json['dayOverrides'] as List<dynamic>? ?? const [])
          _readOverride(item as Map<String, dynamic>),
      ];
      _require(
        {for (final override in overrides) override.date}.length ==
            overrides.length,
      );

      return Backup(
        exportedAt: _readInstant(json['exportedAt'])!,
        settings: settings,
        tasks: tasks,
        dayOverrides: overrides,
      );
    } on BackupFormatException {
      rethrow;
    } on Object {
      // Wrong JSON, a missing field, a wrong type, a broken rule.
      throw const BackupFormatException(BackupProblem.notABackup);
    }
  }

  static Map<String, Object?> _settings(Settings settings) => {
    'priorityScale': settings.priorityScale,
    'weeklyCapacity': settings.weeklyCapacity,
    'maxOverflowPerDay': settings.maxOverflowPerDay,
    'planningHorizonDays': settings.planningHorizonDays,
    'urgencySoonDays': settings.urgencySoonDays,
    'urgencyNearDays': settings.urgencyNearDays,
    'focusVisibleLimit': settings.focusVisibleLimit,
    'dayStartHour': settings.dayStartHour,
  };

  static Settings _readSettings(Map<String, dynamic> json) {
    final scale = json['priorityScale'] as int;
    final capacity = (json['weeklyCapacity'] as List<dynamic>).cast<int>();
    final overflow = json['maxOverflowPerDay'] as int;
    final horizon = json['planningHorizonDays'] as int;
    final soon = json['urgencySoonDays'] as int;
    final near = json['urgencyNearDays'] as int;
    final focusLimit = json['focusVisibleLimit'] as int;
    final dayStart = json['dayStartHour'] as int;
    _require(PriorityLabels.scales.contains(scale));
    _require(capacity.length == 7 && capacity.every((c) => c >= 0));
    _require(overflow >= 0 && overflow <= Settings.maxOverflowLimit);
    _require(horizon >= 1);
    _require(near >= 0 && near <= soon);
    _require(focusLimit >= 1);
    _require(dayStart >= 0 && dayStart <= 23);
    return Settings(
      priorityScale: scale,
      weeklyCapacity: List.unmodifiable(capacity),
      maxOverflowPerDay: overflow,
      planningHorizonDays: horizon,
      urgencySoonDays: soon,
      urgencyNearDays: near,
      focusVisibleLimit: focusLimit,
      dayStartHour: dayStart,
    );
  }

  static Map<String, Object?> _task(Task task) => {
    'id': task.id,
    'title': task.title,
    'notes': ?task.notes,
    'priority': task.priority,
    'dueDate': ?task.dueDate?.toIso(),
    'isFocused': task.isFocused,
    'focusedAt': ?_instantOrNull(task.focusedAt),
    'pinnedDate': ?task.pinnedDate?.toIso(),
    'notBefore': ?task.notBefore?.toIso(),
    'status': task.status.name,
    'createdAt': _instant(task.createdAt),
    'updatedAt': _instant(task.updatedAt),
    'completedAt': ?_instantOrNull(task.completedAt),
    'completedOnPlan': task.completedOnPlan,
    'deletedAt': ?_instantOrNull(task.deletedAt),
  };

  static Task _readTask(Map<String, dynamic> json, int scale) {
    final id = json['id'] as String;
    final title = (json['title'] as String).trim();
    final status = TaskStatus.values.byName(json['status'] as String);
    final isFocused = json['isFocused'] as bool? ?? false;
    final focusedAt = _readInstant(json['focusedAt']);
    final completedAt = _readInstant(json['completedAt']);
    final completedOnPlan = json['completedOnPlan'] as bool? ?? false;
    _require(id.isNotEmpty && title.isNotEmpty);
    _require((status == TaskStatus.done) == (completedAt != null));
    _require(isFocused == (focusedAt != null));
    _require(!completedOnPlan || status == TaskStatus.done);
    return Task(
      id: id,
      title: title,
      notes: json['notes'] as String?,
      priority: (json['priority'] as int).clamp(1, scale),
      dueDate: _readDate(json['dueDate']),
      isFocused: isFocused,
      focusedAt: focusedAt,
      pinnedDate: _readDate(json['pinnedDate']),
      notBefore: _readDate(json['notBefore']),
      status: status,
      createdAt: _readInstant(json['createdAt'])!,
      updatedAt: _readInstant(json['updatedAt'])!,
      completedAt: completedAt,
      completedOnPlan: completedOnPlan,
      deletedAt: _readInstant(json['deletedAt']),
    );
  }

  static DayOverride _readOverride(Map<String, dynamic> json) {
    final capacity = json['capacity'] as int;
    _require(capacity >= 0);
    return DayOverride(
      date: _readDate(json['date'])!,
      capacity: capacity,
      note: json['note'] as String?,
    );
  }

  static String _instant(DateTime value) => value.toUtc().toIso8601String();

  static String? _instantOrNull(DateTime? value) =>
      value == null ? null : _instant(value);

  static DateTime? _readInstant(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();

  static LocalDate? _readDate(Object? value) =>
      value == null ? null : LocalDate.parse(value as String);

  static void _require(bool condition) {
    if (!condition) throw const FormatException('not a valid backup');
  }
}
