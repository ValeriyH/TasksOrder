import 'package:tasks_order/data/db/database.dart';
import 'package:tasks_order/domain/model/task.dart';

extension TaskRowMapper on TaskRow {
  Task toDomain() => Task(
    id: id,
    title: title,
    notes: notes,
    priority: priority,
    dueDate: dueDate,
    isFocused: isFocused,
    focusedAt: focusedAt,
    pinnedDate: pinnedDate,
    notBefore: notBefore,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    completedAt: completedAt,
    completedOnPlan: completedOnPlan,
    deletedAt: deletedAt,
  );
}

extension TaskMapper on Task {
  TaskRow toRow() => TaskRow(
    id: id,
    title: title,
    notes: notes,
    priority: priority,
    dueDate: dueDate,
    isFocused: isFocused,
    focusedAt: focusedAt,
    pinnedDate: pinnedDate,
    notBefore: notBefore,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    completedAt: completedAt,
    completedOnPlan: completedOnPlan,
    deletedAt: deletedAt,
  );
}
