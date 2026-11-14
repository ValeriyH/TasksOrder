import 'package:tasks_order/domain/model/backup.dart';

/// Reads and replaces the whole content of the store, for backup and restore.
abstract interface class BackupRepository {
  /// Everything that is stored now, the Trash included; [now] becomes
  /// `Backup.exportedAt`.
  Future<Backup> read(DateTime now);

  /// Replaces all tasks, capacity overrides and planning settings with the
  /// content of [backup], in one step: either everything or nothing changes.
  /// Tasks keep their own timestamps; settings and overrides are stamped
  /// with [now].
  Future<void> replaceAll(Backup backup, DateTime now);
}

/// Where backup files go to and come from: a place the user picks, outside
/// the app, so the file survives a reinstall.
abstract interface class BackupFileStore {
  /// Asks the user where to save [content] under the suggested [fileName].
  /// False when the user cancelled.
  Future<bool> save(String fileName, String content);

  /// Asks the user for a file and returns its text; null when the user
  /// cancelled. Throws [FormatException] when the file is not text.
  Future<String?> pick();
}
