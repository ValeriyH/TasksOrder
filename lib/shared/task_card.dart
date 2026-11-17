import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/model/task_size.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/priority_text.dart';
import 'package:tasks_order/shared/repeat_text.dart';
import 'package:tasks_order/shared/task_size_text.dart';

/// The calendar day as a `DateTime`, for date pickers and formatting.
DateTime dateTimeOf(LocalDate date) =>
    DateTime(date.year, date.month, date.day);

/// A short date with the weekday, for example "Wed, Nov 18".
String shortDate(BuildContext context, LocalDate date) =>
    MaterialLocalizations.of(context).formatMediumDate(dateTimeOf(date));

/// Text styles of the task card (D22, card v2 of T-1103).
abstract final class _Text {
  static const title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 24 / 18,
  );
  static const due = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const chip = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const button = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
}

/// A task in a list, the "quiet card" (D22, card v2 of T-1103): the title,
/// the chips under it, and a bottom row with the due line (only for a due
/// date, or the day of a done task) and the Done button at the right.
///
/// The chips the task itself knows (priority, focus unless [showFocus] is
/// off: Today has a Focus section, pin, repeat, size, allowed days, paused,
/// "from" a date) and the [chips] of the list (planned day, over plan, at
/// risk, reasons) are shown together in the order of [ChipSlot], the
/// priority first; all of them, wrapped onto more lines when needed.
///
/// A done task ([isDone]) is dimmed with its title struck through, every
/// chip quiet and a grey priority dot, and its button reads "Completed"; a
/// tap on it calls [onToggleDone] again, which the screen turns into an
/// undo.
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.scale,
    required this.today,
    required this.onToggleDone,
    required this.onTap,
    this.isDone = false,
    this.paused = false,
    this.locked = false,
    this.showFocus = true,
    this.showPinDate = true,
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

  /// A done card of an older completion of a series (T-713): it cannot be
  /// taken back, so the Completed button is dimmed. A press still calls
  /// [onToggleDone], which explains instead of taking it back.
  final bool locked;

  /// Show the focus chip of a focused task.
  final bool showFocus;

  /// The pin chip says "Pinned to {date}" (T-911); off where the list adds
  /// its own "Planned for {date}" chip, so the date is not said twice.
  final bool showPinDate;

  /// Chips of the list the card is in; placed by their [TaskChip.slot].
  final List<TaskChip> chips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final dueDate = task.dueDate;
    final overdueDays = dueDate == null ? 0 : dueDate.daysUntil(today);
    final overdue = overdueDays > 0 && !isDone;
    final pinned = task.pinnedDate;
    final rule = task.recurrence;
    // Not released yet (D20): the planner keeps it until that day. A pin
    // leads (T-714): the pinned day is the one that counts.
    final release = task.notBefore;
    final waits =
        release != null && release > today && !isDone && pinned == null;

    final doneOn = isDone ? this.doneOn : null;
    final dueText = switch (dueDate) {
      _ when doneOn != null => switch (doneOn.daysUntil(today)) {
        0 => l10n.completedToday,
        1 => l10n.completedYesterday,
        _ => l10n.completedOn(shortDate(context, doneOn)),
      },
      // No due date: no due line (T-1103); the planned day is a chip.
      null => null,
      _ when overdueDays > 0 => l10n.overdueBy(overdueDays),
      _ when overdueDays == 0 => l10n.dueToday,
      final date => l10n.dueOn(shortDate(context, date)),
    };
    final dueColor = overdue ? c.alert : c.muted;

    final all = <TaskChip>[
      if (showFocus && task.isFocused)
        TaskChip(
          label: l10n.taskFocusLabel,
          icon: Icons.center_focus_strong_outlined,
          slot: ChipSlot.focus,
        ),
      if (pinned != null)
        TaskChip(
          label: showPinDate
              ? l10n.pinnedTo(shortDate(context, pinned))
              : l10n.reasonPinned,
          icon: Icons.push_pin_outlined,
          slot: ChipSlot.pinned,
        ),
      if (rule != null)
        TaskChip(
          label: repeatSummary(l10n, rule),
          icon: Icons.repeat,
          slot: ChipSlot.repeat,
        ),
      // Small and large only: a normal task needs no mark (D21).
      if (TaskSize.nearest(task.weight) case final size
          when size != TaskSize.normal)
        TaskChip(
          key: const ValueKey('sizeChip'),
          label: sizeLabel(l10n, size),
          icon: size == TaskSize.small ? Icons.unfold_less : Icons.unfold_more,
          slot: ChipSlot.size,
        ),
      // Planned only on these days of the week (D23).
      if (task.allowedWeekdays case final days?)
        TaskChip(
          key: const ValueKey('daysChip'),
          label: l10n.onlyDays(weekdaysText(l10n, days)),
          icon: Icons.date_range,
          slot: ChipSlot.days,
        ),
      if (waits)
        TaskChip(
          label: l10n.availableFrom(shortDate(context, release)),
          icon: Icons.hourglass_empty,
          slot: ChipSlot.from,
        ),
      if (paused)
        TaskChip(
          label: l10n.taskPausedBadge,
          icon: Icons.pause_circle_outline,
          slot: ChipSlot.paused,
        ),
      ...chips,
    ];

    return AnimatedOpacity(
      duration: AppDims.doneFade,
      opacity: isDone ? AppDims.doneOpacity : 1,
      child: _CardShell(
        onTap: onTap,
        children: [
          _CardTitle(task.title, isDone: isDone),
          const SizedBox(height: AppDims.cardGap),
          _ChipRow(
            priority: PriorityChip(
              priority: task.priority,
              scale: scale,
              isDone: isDone,
            ),
            chips: all,
            quiet: isDone,
          ),
          const SizedBox(height: AppDims.cardGap),
          Row(
            children: [
              if (dueText != null) ...[
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
              ] else
                const Spacer(),
              Opacity(
                opacity: (paused && !isDone) || (locked && isDone) ? 0.38 : 1,
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

/// The title of a card: two lines at most (T-1103); struck through when
/// the task is done.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.isDone = false});

  final String title;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _Text.title.copyWith(
        color: isDone ? c.titleDone : c.title,
        decoration: isDone ? TextDecoration.lineThrough : null,
        decorationColor: c.titleDone,
      ),
    );
  }
}

/// The priority, then [chips] in the order of their [ChipSlot] (the list's
/// own order inside a slot), wrapped onto more lines when needed. [quiet]:
/// a done task, every chip neutral (T-1103).
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.priority,
    required this.chips,
    this.quiet = false,
  });

  final PriorityChip priority;
  final List<TaskChip> chips;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final sorted = [...chips.indexed]
      ..sort((a, b) {
        final c = a.$2.slot.index.compareTo(b.$2.slot.index);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return Wrap(
      spacing: AppDims.chipSpacing,
      runSpacing: AppDims.chipSpacing,
      children: [
        priority,
        for (final (_, chip) in sorted) quiet ? chip.quiet() : chip,
      ],
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
  final List<TaskChip> chips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rule = task.recurrence;
    return Opacity(
      opacity: 0.6,
      child: Tooltip(
        message: l10n.ghostTooltip,
        child: _CardShell(
          onTap: onTap,
          children: [
            _CardTitle(task.title),
            const SizedBox(height: AppDims.cardGap),
            _ChipRow(
              priority: PriorityChip(priority: task.priority, scale: scale),
              chips: [
                if (rule != null)
                  TaskChip(
                    label: repeatSummary(l10n, rule),
                    icon: Icons.repeat,
                    slot: ChipSlot.repeat,
                  ),
                ...chips,
              ],
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

/// How a [TaskChip] is coloured (card v2 of T-1103): quiet chips are grey
/// with [AppColors.metaText]; only "At risk" stays loud.
enum ChipTone {
  /// Focus, pin, repeat, planned day, size, days, paused, from, reasons.
  neutral,

  /// Over plan: the text in [AppColors.metaExtra] on the grey chip.
  extra,

  /// At risk: red.
  alert,
}

/// Where a [TaskChip] stands on a card (T-1103): the important ones first.
/// The priority chip is always before all of them.
enum ChipSlot {
  atRisk,
  focus,
  pinned,
  overPlan,
  repeat,
  planned,
  size,
  days,
  from,
  paused,
  waitsForRoom,
  deadline,
}

/// A small rounded label on a task card.
class TaskChip extends StatelessWidget {
  const TaskChip({
    required this.label,
    required this.slot,
    this.icon,
    this.tone = ChipTone.neutral,
    super.key,
  });

  final String label;
  final IconData? icon;
  final ChipTone tone;

  /// Its place among the chips of a card.
  final ChipSlot slot;

  /// The same chip, neutral: on a done card every chip is quiet (T-1103).
  TaskChip quiet() => tone == ChipTone.neutral
      ? this
      : TaskChip(key: key, label: label, slot: slot, icon: icon);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (background, foreground) = switch (tone) {
      ChipTone.neutral => (c.neutralChipBg, c.metaText),
      ChipTone.extra => (c.neutralChipBg, c.metaExtra),
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

/// The priority of a task (D1, card v2 of T-1103): a dot in the colour of
/// the level and its name. Quiet (grey chip, [AppColors.metaText]) but for
/// the loud levels, Catastrophic and Critical ([isLoud]), which keep the
/// tint and the text of their own colour. A done task's chip is quiet with
/// a grey dot.
class PriorityChip extends StatelessWidget {
  const PriorityChip({
    required this.priority,
    required this.scale,
    this.isDone = false,
    super.key,
  });

  final int priority;
  final int scale;
  final bool isDone;

  /// Levels 1 (Catastrophic) and 2 (Critical) of the ten-level table
  /// (ADR-17): the only priorities with a coloured chip (owner, T-1103).
  static bool isLoud(int priority) => priority <= 2;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shade = priorityShade(context, priority, scale);
    final loud = isLoud(priority) && !isDone;
    // The dot: the colour of the level itself in the light theme, its light
    // shade in the dark one (a dark red does not read on a dark chip).
    final dot = isDone
        ? c.priorityDotDone
        : Theme.of(context).brightness == Brightness.dark
        ? shade.foreground
        : priorityColor(priority, scale);
    final text = loud ? shade.foreground : c.metaText;
    return _ChipShell(
      key: const ValueKey('priorityChip'),
      background: loud ? shade.background : c.neutralChipBg,
      children: [
        Container(
          key: const ValueKey('priorityDot'),
          width: AppDims.priorityDot,
          height: AppDims.priorityDot,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            priorityName(context.l10n, priority, scale),
            overflow: TextOverflow.ellipsis,
            style: _Text.chip.copyWith(color: text),
          ),
        ),
      ],
    );
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.background,
    required this.children,
    super.key,
  });

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
