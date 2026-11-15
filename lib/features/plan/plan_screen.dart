import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';
import 'package:tasks_order/app/router.dart';
import 'package:tasks_order/application/device_settings_providers.dart';
import 'package:tasks_order/application/providers.dart';
import 'package:tasks_order/domain/model/day_override.dart';
import 'package:tasks_order/domain/model/local_date.dart';
import 'package:tasks_order/domain/model/plan.dart';
import 'package:tasks_order/domain/model/task.dart';
import 'package:tasks_order/domain/planner/capacity_resolver.dart';
import 'package:tasks_order/domain/planner/planner.dart';
import 'package:tasks_order/features/plan/day_override_dialog.dart';
import 'package:tasks_order/l10n/l10n.dart';
import 'package:tasks_order/shared/at_risk_sheet.dart';
import 'package:tasks_order/shared/plan_badges.dart';
import 'package:tasks_order/shared/screen_header.dart';
import 'package:tasks_order/shared/task_actions_ui.dart';
import 'package:tasks_order/shared/task_card.dart';

/// The coming days of the plan (D22): which task lands on which day, how
/// full each day is, and the room left on it.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plan = ref.watch(planProvider);

    return Scaffold(
      body: TabBody(
        child: switch (plan) {
          AsyncValue(:final value?) => _PlanBody(plan: value),
          AsyncValue(hasError: true) => Center(child: Text(l10n.errorLoading)),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// A date as the head of a day: "Tue, 17 November", the weekday with a
/// capital.
String dayTitle(BuildContext context, LocalDate date) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final text = DateFormat('EEE, d MMMM', locale).format(dateTimeOf(date));
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// The days of the plan: "15 – 21 November", or "28 November – 4 December"
/// over a month end, with the year only where the two differ.
String dateRange(BuildContext context, LocalDate first, LocalDate last) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  String format(String pattern, LocalDate date) =>
      DateFormat(pattern, locale).format(dateTimeOf(date));
  if (first == last) return format('d MMMM', first);
  final end = last.year != first.year
      ? format('d MMMM y', last)
      : format('d MMMM', last);
  final start = first.year != last.year
      ? format('d MMMM y', first)
      : first.month == last.month
      ? format('d', first)
      : format('d MMMM', first);
  return '$start – $end';
}

class _PlanBody extends ConsumerWidget {
  const _PlanBody({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    // The plan was computed from these, so they have arrived.
    final tasks = ref.watch(allTasksProvider).requireValue;
    final settings = ref.watch(settingsProvider).requireValue;
    final overrides = ref.watch(dayOverridesProvider).requireValue;
    final showReasons = ref.watch(
      deviceSettingsProvider.select((settings) => settings.showReasons),
    );

    final paused = ref.watch(pausedTaskIdsProvider);
    final older = ref.watch(olderCompletionIdsProvider);
    final byId = {for (final task in tasks) task.id: task};
    final today = plan.today;
    final scale = settings.priorityScale;
    final resolver = CapacityResolver(settings, overrides);
    // Today counts what was done from its list too, against the full
    // capacity: the numbers of the Today screen (D19).
    final doneFromList = Planner.countCompletedToday(
      tasks,
      today: today,
      dayStartHour: settings.dayStartHour,
    );
    // A done task stays at the end of the day the plan had it on, dimmed,
    // until that day is past (T-907, D22); its slot is planned again.
    final done = [
      for (final task in tasks)
        if (task.isDone && !task.isDeleted) task,
    ]..sort((a, b) => a.completedAt!.compareTo(b.completedAt!));
    List<Task> doneOn(LocalDate day) => [
      for (final task in done)
        if (Planner.keptOnDay(
          task,
          day,
          today: today,
          dayStartHour: settings.dayStartHour,
        ))
          task,
    ];

    Widget card(
      Task task, {
      required LocalDate? plannedDate,
      bool isDone = false,
      List<Widget> chips = const [],
    }) => TaskCard(
      key: ValueKey(task.id),
      task: task,
      scale: scale,
      today: today,
      isDone: isDone,
      doneOn: isDone
          ? Planner.completionDay(task, settings.dayStartHour)
          : null,
      paused: !isDone && paused.contains(task.id),
      locked: isDone && older.contains(task.id),
      chips: chips,
      onTap: () => unawaited(showTaskMenu(context, ref, task, today)),
      onToggleDone: () => unawaited(
        toggleDone(
          context,
          ref,
          task,
          onPlan: plannedDate == today,
          plannedDate: plannedDate,
          isDone: isDone,
        ),
      ),
    );

    final later = [for (final id in plan.laterTaskIds) ?byId[id]];
    final days = plan.days;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ScreenHeader(
          subtitle: days.isEmpty
              ? ''
              : dateRange(context, days.first.date, days.last.date),
          title: l10n.tabPlan,
        ),
        if (plan.hasAtRisk)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Material(
              color: c.capOverBg,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: c.capOverFg),
                title: Text(
                  l10n.planAtRisk(plan.atRiskTaskIds.length),
                  style: TextStyle(
                    color: c.capOverFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: c.capOverFg),
                onTap: () => unawaited(showAtRiskList(context)),
              ),
            ),
          ),
        for (final day in days)
          ..._day(
            context,
            ref,
            day: day,
            today: today,
            capacity: resolver.capacityFor(day.date),
            count: day.entries.length + (day.date == today ? doneFromList : 0),
            dayOverride: overrides[day.date],
            cards: [
              for (final entry in day.entries)
                if (byId[entry.taskId] case final task?)
                  // A coming repeat of a recurring task (T-704): the date
                  // keeps its key apart from the task's own card.
                  if (entry.occurrenceDate case final occurrence?)
                    GhostTaskCard(
                      key: ValueKey('${task.id}@$occurrence'),
                      task: task,
                      scale: scale,
                      onTap: () =>
                          unawaited(context.push(AppRoutes.task(task.id))),
                      chips: planEntryChips(
                        context,
                        entry,
                        showReasons: showReasons,
                        overPlan: true,
                      ),
                    )
                  else
                    card(
                      task,
                      plannedDate: day.date,
                      chips: planEntryChips(
                        context,
                        entry,
                        showReasons: showReasons,
                        overPlan: true,
                      ),
                    ),
              for (final task in doneOn(day.date))
                card(task, plannedDate: day.date, isDone: true),
            ],
          ),
        if (later.isNotEmpty) ...[
          SectionHeader(
            key: const ValueKey('later'),
            icon: Icons.schedule,
            title: l10n.plannedLater,
            counter: '${later.length}',
          ),
          for (final task in later) card(task, plannedDate: null),
        ],
      ],
    );
  }

  /// A day: its head, its cards and the room left on it.
  List<Widget> _day(
    BuildContext context,
    WidgetRef ref, {
    required PlannedDay day,
    required LocalDate today,
    required int capacity,
    required int count,
    required DayOverride? dayOverride,
    required List<Widget> cards,
  }) => [
    _DayHeader(
      date: day.date,
      today: today,
      count: count,
      capacity: capacity,
      dayOverride: dayOverride,
      onTap: () => unawaited(
        showDayOverrideDialog(
          context,
          ref,
          date: day.date,
          capacity: capacity,
          override: dayOverride,
        ),
      ),
    ),
    ...cards,
    if (capacity > count)
      _FreeSlots(
        key: ValueKey('free-${day.date.toIso()}'),
        count: capacity - count,
      ),
  ];
}

/// The head of a day (D22): its name, "· rest day", how full it is and the
/// button that changes its capacity. A tap anywhere on it does the same.
/// Keyed `ValueKey('day-<iso date>')`.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.date,
    required this.today,
    required this.count,
    required this.capacity,
    required this.dayOverride,
    required this.onTap,
  });

  final LocalDate date;
  final LocalDate today;

  /// Tasks the day holds; for today the ones done from its list too.
  final int count;

  /// The day's full capacity; 0 is a rest day.
  final int capacity;

  /// The capacity set for this date, when there is one.
  final DayOverride? dayOverride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final isToday = date == today;
    final note = dayOverride?.note;
    final restDay = capacity == 0;
    final small = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: c.muted,
    );

    return InkWell(
      key: ValueKey('day-${date.toIso()}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDims.minTapTarget),
          child: Row(
            children: [
              if (isToday) ...[
                Icon(Icons.today_outlined, size: 20, color: c.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: switch (today.daysUntil(date)) {
                      0 => l10n.dateToday,
                      1 => l10n.dateTomorrow,
                      _ => dayTitle(context, date),
                    },
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isToday ? c.todayName : c.title,
                    ),
                    children: [
                      if (restDay)
                        TextSpan(text: l10n.planRestDayNote, style: small),
                      if (note != null && note.isNotEmpty)
                        TextSpan(text: '  $note', style: small),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!(restDay && count == 0))
                CapacityPill(count: count, capacity: capacity),
              IconButton(
                key: ValueKey('tune-${date.toIso()}'),
                onPressed: onTap,
                tooltip: dayOverride != null
                    ? l10n.planChangedCapacity
                    : l10n.overrideTitle(shortDate(context, date)),
                icon: Icon(
                  Icons.tune,
                  color: dayOverride != null ? c.accent : c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How full a day is (D22): a dot for each slot, filled for the taken ones,
/// and "count/capacity"; over capacity a red pill with an alert icon.
class CapacityPill extends StatelessWidget {
  const CapacityPill({required this.count, required this.capacity, super.key});

  final int count;
  final int capacity;

  /// More slots than this read better as the number alone.
  static const maxDots = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = AppColors.of(context);
    final over = count > capacity;
    final dots = !over && capacity > 0 && capacity <= maxDots;
    final foreground = over ? c.capOverFg : c.capPillFg;
    return Container(
      height: AppDims.capPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: over ? c.capOverBg : c.capPillBg,
        borderRadius: BorderRadius.circular(14),
        border: over ? null : Border.all(color: c.track),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (over) Icon(Icons.error_outline, size: 14, color: foreground),
          if (dots)
            for (var i = 0; i < capacity; i++)
              Padding(
                padding: EdgeInsets.only(right: i == capacity - 1 ? 0 : 3),
                child: Container(
                  width: AppDims.capDot,
                  height: AppDims.capDot,
                  decoration: BoxDecoration(
                    color: i < count ? c.accent : c.dotOff,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          if (over || dots) const SizedBox(width: 6),
          Text(
            l10n.planDayCount(count, capacity),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// The room left on a day: a dashed box "N slots free" (D22).
class _FreeSlots extends StatelessWidget {
  const _FreeSlots({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: AppDims.cardMargin,
      child: CustomPaint(
        painter: _DashedBorder(color: c.freeBorder),
        child: SizedBox(
          height: AppDims.freeSlotHeight,
          child: Center(
            child: Text(
              context.l10n.planFreeSlots(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(14),
        ).deflate(0.75),
      );
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.color != color;
}
