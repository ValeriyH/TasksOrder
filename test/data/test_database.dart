import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:tasks_order/data/db/database.dart';

/// A fresh in-memory database for one test. Close it in `tearDown`.
///
/// Lives in `test/` because `drift/native.dart` needs `dart:ffi`, which would
/// break the web build if `lib/` imported it.
AppDatabase newTestDatabase() => AppDatabase(
  DatabaseConnection(
    NativeDatabase.memory(),
    // No pending timers after `close()` in tests that listen to streams.
    closeStreamsSynchronously: true,
  ),
);
