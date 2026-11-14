import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/data/backup/backup_codec.dart';
import 'package:tasks_order/domain/model/backup.dart';
import 'package:tasks_order/domain/model/settings.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/repository/backup_repository.dart';
import 'package:tasks_order/shared/task_tile.dart';

import 'app_harness.dart';

/// Stands in for the file dialogs: remembers what was saved and hands out
/// [content] as the picked file.
class FakeBackupFiles implements BackupFileStore {
  FakeBackupFiles({this.content, this.cancel = false, this.broken = false});

  /// Text of the file the user "picks"; null = the user cancels.
  String? content;

  /// The user closes the "save as" dialog.
  bool cancel;

  /// The file system fails.
  bool broken;

  String? savedName;
  String? saved;

  @override
  Future<bool> save(String fileName, String content) async {
    if (broken) throw Exception('disk full');
    if (cancel) return false;
    savedName = fileName;
    saved = content;
    return true;
  }

  @override
  Future<String?> pick() async {
    if (broken) throw Exception('no access');
    return content;
  }
}

void main() {
  /// Starts the app on a tall screen and opens the Settings tab.
  Future<AppHarness> start(
    WidgetTester tester,
    FakeBackupFiles files, {
    List<Task> tasks = const [],
    Settings? settings,
    Map<String, Object> stored = const {},
  }) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await AppHarness.start(
      tester,
      tasks: tasks,
      settings: settings,
      stored: stored,
      backupFiles: files,
    );
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    return app;
  }

  /// Lets the database and the "file" answer, which they do outside the fake
  /// clock of the test, and the screen follow.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  /// A backup file with the tasks [ids] and a priority scale of 10, made on
  /// the harness day.
  String backupOf(List<String> ids) => const BackupCodec().encode(
    Backup(
      exportedAt: AppHarness.now.toUtc(),
      settings: Settings(priorityScale: 10),
      tasks: [for (final (i, id) in ids.indexed) testTask(id, minute: i)],
      dayOverrides: const [],
    ),
  );

  /// Ids of the stored tasks. Read from the store: the task list of the app
  /// is paused while the Settings tab is open.
  Future<List<String>> ids(AppHarness app) async => [
    for (final task in await app.real(
      () => app.container.read(taskRepositoryProvider).watchAll().first,
    ))
      task.id,
  ];

  testWidgets('save writes all tasks and settings to a dated file', (
    tester,
  ) async {
    final files = FakeBackupFiles();
    await start(
      tester,
      files,
      tasks: [testTask('a'), testTask('b', minute: 1)],
      settings: Settings(priorityScale: 10),
    );
    expect(find.text('Backup'), findsOneWidget);

    await tapKey(tester, 'backupSave');

    expect(files.savedName, 'tasksorder-backup-2026-11-13.json');
    final json = jsonDecode(files.saved!) as Map<String, dynamic>;
    expect(json['app'], 'TasksOrder');
    expect(
      (json['tasks'] as List<dynamic>).map(
        (task) => (task as Map<String, dynamic>)['title'],
      ),
      ['Task a', 'Task b'],
    );
    expect((json['settings'] as Map<String, dynamic>)['priorityScale'], 10);
    expect(find.text('Backup saved'), findsOneWidget);
  });

  testWidgets('a cancelled save says nothing', (tester) async {
    final files = FakeBackupFiles(cancel: true);
    await start(tester, files);

    await tapKey(tester, 'backupSave');

    expect(files.saved, isNull);
    expect(find.text('Backup saved'), findsNothing);
  });

  testWidgets('a failed save is reported', (tester) async {
    await start(tester, FakeBackupFiles(broken: true));

    await tapKey(tester, 'backupSave');

    expect(find.text('Could not save the backup'), findsOneWidget);
  });

  testWidgets('restore asks, then replaces tasks and settings', (tester) async {
    final file = backupOf(['x', 'y', 'z']);
    final app = await start(
      tester,
      FakeBackupFiles(content: file),
      tasks: [testTask('old')],
    );

    await tapKey(tester, 'backupRestore');
    expect(find.text('Restore from this backup?'), findsOneWidget);
    expect(
      find.textContaining('The backup of Fri, Nov 13 holds 3 tasks.'),
      findsOneWidget,
    );
    expect(find.textContaining('everything in the app: 1 task,'), findsOne);
    // Nothing changed yet.
    expect(await ids(app), ['old']);

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await settle(tester);

    expect(await ids(app), ['x', 'y', 'z']);
    expect(app.container.read(settingsProvider).requireValue.priorityScale, 10);
    expect(find.text('Restored from the backup'), findsOneWidget);

    // The plan follows: the first task of the backup is on Today.
    await tester.tap(find.byIcon(Icons.today_outlined));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TaskTile, 'Task x'), findsOneWidget);
  });

  testWidgets('Cancel keeps everything', (tester) async {
    final file = backupOf(['x']);
    final app = await start(
      tester,
      FakeBackupFiles(content: file),
      tasks: [testTask('old')],
    );

    await tapKey(tester, 'backupRestore');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await ids(app), ['old']);
    expect(app.container.read(settingsProvider).requireValue.priorityScale, 5);
  });

  testWidgets('no file picked: no question', (tester) async {
    final app = await start(
      tester,
      FakeBackupFiles(),
      tasks: [testTask('old')],
    );

    await tapKey(tester, 'backupRestore');

    expect(find.text('Restore from this backup?'), findsNothing);
    expect(await ids(app), ['old']);
  });

  testWidgets('a file that is not a backup changes nothing', (tester) async {
    final app = await start(
      tester,
      FakeBackupFiles(content: '{"hello": "world"}'),
      tasks: [testTask('old')],
    );

    await tapKey(tester, 'backupRestore');

    expect(find.text('This file is not a TasksOrder backup'), findsOneWidget);
    expect(find.text('Restore from this backup?'), findsNothing);
    expect(await ids(app), ['old']);
  });

  testWidgets('a backup of a newer app version is refused', (tester) async {
    final file = backupOf(['x']);
    final newer = (jsonDecode(file) as Map<String, dynamic>)..['version'] = 99;
    final app = await start(
      tester,
      FakeBackupFiles(content: jsonEncode(newer)),
      tasks: [testTask('old')],
    );

    await tapKey(tester, 'backupRestore');

    expect(find.textContaining('newer version of the app'), findsOneWidget);
    expect(await ids(app), ['old']);
  });

  testWidgets('a file that cannot be opened is reported', (tester) async {
    await start(tester, FakeBackupFiles(broken: true));

    await tapKey(tester, 'backupRestore');

    expect(find.text('Could not read the file'), findsOneWidget);
  });

  testWidgets('in Ukrainian', (tester) async {
    final file = backupOf(['x', 'y']);
    await start(
      tester,
      FakeBackupFiles(content: file),
      stored: {'device.locale': 'uk'},
    );
    expect(find.text('Резервна копія'), findsOneWidget);
    expect(find.text('Зберегти резервну копію'), findsOneWidget);

    await tapKey(tester, 'backupRestore');

    expect(find.text('Відновити з цієї копії?'), findsOneWidget);
    expect(find.textContaining('містить 2 завдання.'), findsOneWidget);
    expect(find.textContaining('0 завдань, кошик'), findsOneWidget);
  });
}
