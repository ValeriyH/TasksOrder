import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:tasks_order/app/app_shell.dart';
import 'package:tasks_order/features/plan/plan_screen.dart';
import 'package:tasks_order/features/settings/settings_screen.dart';
import 'package:tasks_order/features/task_edit/task_edit_screen.dart';
import 'package:tasks_order/features/tasks/tasks_screen.dart';
import 'package:tasks_order/features/today/today_screen.dart';
import 'package:tasks_order/features/trash/trash_screen.dart';

part 'router.g.dart';

/// Locations of the app. Tabs are opened with `context.go`, the editor with
/// `context.push`, so that "back" returns to the tab it was opened from.
abstract final class AppRoutes {
  static const today = '/today';
  static const plan = '/plan';
  static const tasks = '/tasks';
  static const settings = '/settings';
  static const taskNew = '/task/new';
  static const trash = '/trash';

  /// The editor of the task with [id].
  static String task(String id) => '/task/${Uri.encodeComponent(id)}';
}

/// Four tabs that keep their own state, and the task editor above them.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.today,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        // The order is the order of the tabs in AppShell.
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.today,
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.plan,
                builder: (context, state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tasks,
                builder: (context, state) => const TasksScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.trash,
        builder: (context, state) => const TrashScreen(),
      ),
      // Before '/task/:id', or "new" would be taken for an id.
      GoRoute(
        path: AppRoutes.taskNew,
        builder: (context, state) => const TaskEditScreen(),
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) =>
            TaskEditScreen(taskId: state.pathParameters['id']),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}
