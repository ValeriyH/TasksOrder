import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:tasks_order/domain/repository/backup_repository.dart';

/// [BackupFileStore] with the system dialogs: "save as" and "open file" on
/// Android and Windows, a download and a file chooser in the browser.
class PickerBackupFileStore implements BackupFileStore {
  const PickerBackupFileStore();

  @override
  Future<bool> save(String fileName, String content) async {
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: utf8.encode(content),
      mimeType: 'application/json',
    );
    return saved != null;
  }

  @override
  Future<String?> pick() async {
    // No filter by extension: some file providers on Android then hide JSON
    // files. The content is checked instead.
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes());
  }
}
