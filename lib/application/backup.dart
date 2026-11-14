import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/backup/backup_codec.dart';
import 'package:tasks_order/data/backup/picker_backup_file_store.dart';
import 'package:tasks_order/data/repository/drift_backup_repository.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/repository/backup_repository.dart';

part 'backup.g.dart';

@Riverpod(keepAlive: true)
BackupRepository backupRepository(Ref ref) =>
    DriftBackupRepository(ref.watch(databaseProvider));

/// Where backup files are saved and picked. Tests override it.
@Riverpod(keepAlive: true)
BackupFileStore backupFileStore(Ref ref) => const PickerBackupFileStore();

@Riverpod(keepAlive: true)
BackupService backupService(Ref ref) => BackupService(
  ref.watch(backupRepositoryProvider),
  ref.watch(backupFileStoreProvider),
  ref.watch(clockProvider),
);

/// Backup to a file and restore from one (T-502).
class BackupService {
  const BackupService(this._repository, this._files, this._clock);

  static const _codec = BackupCodec();

  final BackupRepository _repository;
  final BackupFileStore _files;
  final Clock _clock;

  /// Writes everything to a file the user places. False when the user
  /// cancelled.
  Future<bool> save() async {
    final now = _clock();
    final backup = await _repository.read(now);
    final day = LocalDate.fromDateTime(now.toLocal()).toIso();
    return _files.save('tasksorder-backup-$day.json', _codec.encode(backup));
  }

  /// Lets the user pick a backup file and reads it; null when the user
  /// cancelled. Changes nothing: [restore] does. Throws
  /// [BackupFormatException] when the file is not a backup this app can read.
  Future<Backup?> pick() async {
    final String? text;
    try {
      text = await _files.pick();
    } on FormatException {
      // Not text at all.
      throw const BackupFormatException(BackupProblem.notABackup);
    }
    return text == null ? null : _codec.decode(text);
  }

  /// How many tasks the app holds now, the Trash aside: what a restore
  /// would replace.
  Future<int> currentTaskCount() async =>
      (await _repository.read(_clock())).taskCount;

  /// Replaces everything in the app with the content of [backup].
  Future<void> restore(Backup backup) =>
      _repository.replaceAll(backup, _clock());
}
