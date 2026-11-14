import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';

/// Everything the user entered, at one moment: what a backup file holds.
///
/// Device settings (language, theme) are not part of it: they belong to the
/// device, not to the data (D12).
class Backup {
  const Backup({
    required this.exportedAt,
    required this.settings,
    required this.tasks,
    required this.dayOverrides,
  });

  /// UTC instant the backup was made.
  final DateTime exportedAt;
  final Settings settings;

  /// Active, done and deleted tasks: the Trash comes back too.
  final List<Task> tasks;
  final List<DayOverride> dayOverrides;

  /// Tasks outside the Trash: the number shown to the user.
  int get taskCount => tasks.where((task) => !task.isDeleted).length;
}

/// Why a file could not be read as a backup.
enum BackupProblem {
  /// Not a backup of this app, or a damaged one.
  notABackup,

  /// Written by a newer version of the app, in a format this one does not
  /// know.
  newerVersion,
}

/// Thrown when a backup file cannot be read. Nothing is changed in that case.
class BackupFormatException implements Exception {
  const BackupFormatException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupFormatException(${problem.name})';
}
