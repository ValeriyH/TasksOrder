import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';
import 'package:tasks_order/shared/repeat_text.dart';

/// The calendar day as a `DateTime`, for date pickers and formatting.
DateTime dateTimeOf(LocalDate date) =>
    DateTime(date.year, date.month, date.day);

/// A short date with the weekday, for example "Wed, Nov 18".
String shortDate(BuildContext context, LocalDate date) =>
    MaterialLocalizations.of(context).formatMediumDate(dateTimeOf(date));

/// Text styles of the task card (D22).
abstract final class _Text {
  static const title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 23 / 17,
  );
  static const due = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const chip = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const button = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
}

/// A task in a list (D22): a row of chips, the title, the due line and the
/// Done button.
///
/// The chips the task itself knows come first: priority, focus (unless
/// [showFocus] is off: Today has a Focus section), pin, repeat; then the
/// [chips] of the list (planned day, over plan, at risk, reasons); then
/// "paused" and "from" a date. A done task ([isDone]) is dimmed with its
/// title struck through, and its button reads "Completed"; a tap on it calls
/// [onToggleDone] again, which the screen turns into an undo.
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.scale,
    required this.today,
    required this.onToggleDone,
    required this.onTap,
    this.isDone = false,
    this.paused = false,
    this.showFocus = true,
    this.chips = const [],
    this.doneOn,
    super.key,
  });

  final Task task;

  /// The priority scale of the settings.
  final int scale;
  final LocalDate today;

  /// The planning day the task was completed on (D15): a done card shows
  /// "Completed today", "Completed yesterday" or the date in place of the
  /// due line.
  final LocalDate? doneOn;

  /// The Done or the Completed button was pressed.
  final VoidCallback onToggleDone;

  /// The card was tapped: the screens open the task menu.
  final VoidCallback onTap;

  /// Show the card as done: dimmed, struck through, "Completed".
  final bool isDone;

  /// Its series counts from completion and was completed today (T-710): the
  /// button is dimmed and a chip says so. A press still calls
  /// [onToggleDone], which explains instead of completing.
  final bool paused;

  /// Show the focus chip of a focused task.
  final bool showFocus;

  /// Chips of the list the card is in.
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final dueDate = task.dueDate;
    final overdueDays = dueDate == null ? 0 : dueDate.daysUntil(today);
    final overdue = overdueDays > 0 && !isDone;
    final pinned = task.pinnedDate;
    final rule = task.recurrence;
    // Not released yet (D20): the planner keeps it until that day.
    final release = task.notBefore;
    final waits = release != null && release > today && !isDone;

    final doneOn = isDone ? this.doneOn : null;
    final dueText = switch (dueDate) {
      _ when doneOn != null => switch (doneOn.daysUntil(today)) {
        0 => l10n.completedToday,
        1 => l10n.completedYesterday,
        _ => l10n.completedOn(shortDate(context, doneOn)),
      },
      null => l10n.noDueDate,
      _ when overdueDays > 0 => l10n.overdueBy(overdueDays),
      _ when overdueDays == 0 => l10n.dueToday,
      final date => l10n.dueOn(shortDate(context, date)),
    };
    final dueColor = overdue ? c.alert : c.muted;

    return AnimatedOpacity(
      duration: AppDims.doneFade,
      opacity: isDone ? AppDims.doneOpacity : 1,
      child: _CardShell(
        onTap: onTap,
        children: [
          Wrap(
            spacing: AppDims.chipSpacing,
            runSpacing: AppDims.chipSpacing,
            children: [
              PriorityChip(priority: task.priority, scale: scale),
              if (showFocus && task.isFocused)
                TaskChip(
                  label: l10n.taskFocusLabel,
                  icon: Icons.center_focus_strong_outlined,
                  tone: ChipTone.accent,
                ),
              if (pinned != null)
                TaskChip(
                  label: l10n.reasonPinned,
                  icon: Icons.push_pin_outlined,
                  tone: ChipTone.accent,
                ),
              if (rule != null)
                TaskChip(label: repeatSummary(l10n, rule), icon: Icons.repeat),
              ...chips,
              if (paused)
                TaskChip(
                  label: l10n.taskPausedBadge,
                  icon: Icons.pause_circle_outline,
                ),
              if (waits)
                TaskChip(
                  label: l10n.availableFrom(shortDate(context, release)),
                  icon: Icons.hourglass_empty,
                ),
            ],
          ),
          const SizedBox(height: AppDims.cardGap),
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _Text.title.copyWith(
              color: isDone ? c.titleDone : c.title,
              decoration: isDone ? TextDecoration.lineThrough : null,
              decorationColor: c.titleDone,
            ),
          ),
          const SizedBox(height: AppDims.cardGap),
          Row(
            children: [
              Icon(
                doneOn != null ? Icons.check_circle_outline : Icons.schedule,
                size: 14,
                color: dueColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dueText,
                  overflow: TextOverflow.ellipsis,
                  style: _Text.due.copyWith(color: dueColor),
                ),
              ),
              const SizedBox(width: 12),
              Opacity(
                opacity: paused && !isDone ? 0.38 : 1,
                child: TaskDoneButton(
                  title: task.title,
                  isDone: isDone,
                  onPressed: onToggleDone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A coming repeat of a recurring task in the Plan (a ghost, T-704/T-708):
/// dimmed, no Done button; a tap opens the task the ghost repeats.
class GhostTaskCard extends StatelessWidget {
  const GhostTaskCard({
    required this.task,
    required this.scale,
    required this.onTap,
    this.chips = const [],
    super.key,
  });

  /// The stored task of the series.
  final Task task;
  final int scale;
  final VoidCallback onTap;

  /// Chips of the entry (over plan, at risk, reasons).
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final rule = task.recurrence;
    return Opacity(
      opacity: 0.6,
      child: Tooltip(
        message: l10n.ghostTooltip,
        child: _CardShell(
          onTap: onTap,
          children: [
            Wrap(
              spacing: AppDims.chipSpacing,
              runSpacing: AppDims.chipSpacing,
              children: [
                PriorityChip(priority: task.priority, scale: scale),
                if (rule != null)
                  TaskChip(
                    label: repeatSummary(l10n, rule),
                    icon: Icons.repeat,
                  ),
                ...chips,
              ],
            ),
            const SizedBox(height: AppDims.cardGap),
            Text(
              task.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: _Text.title.copyWith(color: c.title),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded card with its shadow (light theme) and a ripple, the full
/// width of the list less its side margins, with the gap to the next card
/// below it (D22).
class _CardShell extends StatelessWidget {
  const _CardShell({required this.onTap, required this.children});

  final VoidCallback onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = BorderRadius.circular(AppDims.cardRadius);
    return Padding(
      padding: AppDims.cardMargin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: c.cardShadow,
        ),
        child: Material(
          color: c.card,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: AppDims.cardPadding,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Done" (outlined in the accent) or, for a done task, "Completed" (filled,
/// grey). The tap target is at least 44 high (D22).
class TaskDoneButton extends StatelessWidget {
  const TaskDoneButton({
    required this.title,
    required this.isDone,
    required this.onPressed,
    super.key,
  });

  /// The task's title, for the screen reader.
  final String title;
  final bool isDone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    return Semantics(
      container: true,
      button: true,
      toggled: isDone,
      label: isDone ? l10n.markUndoneA11y(title) : l10n.markDoneA11y(title),
      // The button's own node is replaced, so its tap goes here: without it a
      // screen reader could not press the button.
      onTap: onPressed,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(
            AppDims.doneButtonMinWidth,
            AppDims.doneButtonHeight,
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          textStyle: _Text.button,
          foregroundColor: isDone ? c.doneButtonFg : c.accent,
          backgroundColor: isDone ? c.doneButtonBg : Colors.transparent,
          side: isDone
              ? BorderSide.none
              : BorderSide(color: c.accent, width: AppDims.doneButtonBorder),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.check, size: 16),
        label: Text(isDone ? l10n.taskCompletedButton : l10n.taskDoneButton),
      ),
    );
  }
}

/// How a [TaskChip] is coloured (D22).
enum ChipTone {
  /// Repeat, planned day, paused, from: grey.
  neutral,

  /// Focus, pin: the accent.
  accent,

  /// Over plan: amber.
  extra,

  /// At risk: red.
  alert,
}

/// A small rounded label on a task card.
class TaskChip extends StatelessWidget {
  const TaskChip({
    required this.label,
    this.icon,
    this.tone = ChipTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (background, foreground) = switch (tone) {
      ChipTone.neutral => (c.neutralChipBg, c.neutralChipFg),
      ChipTone.accent => (c.accentChipBg, c.accentChipFg),
      ChipTone.extra => (c.extraChipBg, c.extraChipFg),
      ChipTone.alert => (c.capOverBg, c.capOverFg),
    };
    final icon = this.icon;
    return _ChipShell(
      background: background,
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppDims.chipIcon, color: foreground),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: _Text.chip.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}

/// The priority of a task: a dot and its name in the shade of its colour
/// (D1, D22).
class PriorityChip extends StatelessWidget {
  const PriorityChip({required this.priority, required this.scale, super.key});

  final int priority;
  final int scale;

  @override
  Widget build(BuildContext context) {
    final shade = priorityShade(context, priority, scale);
    return _ChipShell(
      background: shade.background,
      children: [
        Container(
          width: AppDims.priorityDot,
          height: AppDims.priorityDot,
          decoration: BoxDecoration(
            color: shade.foreground,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            priorityName(context.l10n, priority, scale),
            overflow: TextOverflow.ellipsis,
            style: _Text.chip.copyWith(color: shade.foreground),
          ),
        ),
      ],
    );
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.background, required this.children});

  final Color background;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    height: AppDims.chipHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppDims.chipHPadding),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppDims.chipRadius),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}
