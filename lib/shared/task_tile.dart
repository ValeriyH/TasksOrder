import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';

/// The calendar day as a `DateTime`, for date pickers and formatting.
DateTime dateTimeOf(LocalDate date) =>
    DateTime(date.year, date.month, date.day);

/// A short date with the weekday, for example "Wed, Nov 18".
String shortDate(BuildContext context, LocalDate date) =>
    MaterialLocalizations.of(context).formatMediumDate(dateTimeOf(date));

/// An active task in a list: a checkbox to complete it, the title and a row
/// of badges (priority, due date or "overdue", then [badges]).
class TaskTile extends StatelessWidget {
  const TaskTile({
    required this.task,
    required this.scale,
    required this.today,
    required this.onCompleted,
    required this.onTap,
    this.onLongPress,
    this.badges = const [],
    this.onMoveDueDate,
    this.onClearDueDate,
    this.paused = false,
    super.key,
  });

  final Task task;

  /// The priority scale of the settings.
  final int scale;
  final LocalDate today;

  /// The checkbox was ticked.
  final VoidCallback onCompleted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Badges of the list the tile is in, after the ones every list shows.
  final List<Widget> badges;

  /// Actions of an overdue task (D18); the menu shows when both are given and
  /// the task is overdue.
  final VoidCallback? onMoveDueDate;
  final VoidCallback? onClearDueDate;

  /// Its series counts from completion and was completed today (T-710): the
  /// checkbox is dimmed and a badge says so. A tick still calls
  /// [onCompleted], which explains instead of completing.
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final priority = task.priority;
    final dueDate = task.dueDate;
    final overdueDays = dueDate == null ? 0 : dueDate.daysUntil(today);
    final moveDueDate = onMoveDueDate;
    final clearDueDate = onClearDueDate;
    // Not released yet (D20): the planner keeps it until that day.
    final release = task.notBefore;
    final waits = release != null && release > today;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Opacity(
        opacity: paused ? 0.38 : 1,
        child: Checkbox(value: false, onChanged: (_) => onCompleted()),
      ),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            TaskBadge(
              label: priorityName(l10n, priority, scale),
              dotColor: priorityColor(priority, scale),
            ),
            if (dueDate != null)
              if (overdueDays > 0)
                TaskBadge(
                  label: l10n.overdueBy(overdueDays),
                  color: colors.error,
                )
              else
                TaskBadge(
                  label: overdueDays == 0
                      ? l10n.dueToday
                      : l10n.dueOn(shortDate(context, dueDate)),
                  icon: Icons.event_outlined,
                ),
            if (paused)
              TaskBadge(
                label: l10n.taskPausedBadge,
                icon: Icons.pause_circle_outline,
              ),
            if (waits)
              TaskBadge(
                label: l10n.availableFrom(shortDate(context, release)),
                icon: Icons.hourglass_empty,
              ),
            ...badges,
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (task.recurrence != null)
            Tooltip(
              message: l10n.repeatTitle,
              child: Icon(Icons.repeat, size: 20, color: colors.outline),
            ),
          if (task.isFocused)
            Tooltip(
              message: l10n.taskFocusLabel,
              child: Icon(
                Icons.center_focus_strong,
                size: 20,
                color: colors.primary,
              ),
            ),
          if (overdueDays > 0 && moveDueDate != null && clearDueDate != null)
            PopupMenuButton<VoidCallback>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: moveDueDate,
                  child: Text(l10n.dueDateMove),
                ),
                PopupMenuItem(
                  value: clearDueDate,
                  child: Text(l10n.dueDateClear),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A coming repeat of a recurring task in the Plan (a ghost, T-704/T-708):
/// dimmed, the repeat icon instead of a checkbox, no menu; a tap opens the
/// task the ghost repeats.
class GhostTaskTile extends StatelessWidget {
  const GhostTaskTile({
    required this.task,
    required this.scale,
    required this.onTap,
    this.badges = const [],
    super.key,
  });

  /// The stored task of the series.
  final Task task;
  final int scale;
  final VoidCallback onTap;

  /// Badges of the entry (reasons).
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        onTap: onTap,
        leading: Padding(
          // Where the checkbox of a task row sits.
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Tooltip(
            message: l10n.ghostTooltip,
            child: Icon(Icons.repeat, color: colors.outline),
          ),
        ),
        title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              TaskBadge(
                label: priorityName(l10n, task.priority, scale),
                dotColor: priorityColor(task.priority, scale),
              ),
              ...badges,
            ],
          ),
        ),
      ),
    );
  }
}

/// A small label under a task title.
class TaskBadge extends StatelessWidget {
  const TaskBadge({
    required this.label,
    this.color,
    this.dotColor,
    this.icon,
    super.key,
  });

  final String label;

  /// Colour of the text and the tinted background; the neutral one by
  /// default.
  final Color? color;

  /// A coloured dot before the label (the priority colour).
  final Color? dotColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color == null
            ? theme.colorScheme.surfaceContainerHighest
            : foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Icon(Icons.circle, size: 8, color: dotColor),
              const SizedBox(width: 4),
            ],
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
