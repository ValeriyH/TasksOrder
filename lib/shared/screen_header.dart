import 'package:material_ui/material_ui.dart';
import 'package:tasks_order/app/app_colors.dart';

/// The top of a tab (D22): a small line above ([subtitle]: a date, a range,
/// a count), the large title, an optional [action] at the right of the
/// title and an optional [bottom] (the progress of Today). The screen keeps
/// it below the status bar ([TabBody]).
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    required this.subtitle,
    this.action,
    this.bottom,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bottom = this.bottom;
    final action = this.action;
    return Padding(
      padding: AppDims.headerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.muted,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.68,
                      color: c.title,
                    ),
                  ),
                ),
              ),
              ?action,
            ],
          ),
          if (bottom != null) ...[const SizedBox(height: 14), bottom],
        ],
      ),
    );
  }
}

/// The header of a section of a list (D22): an icon, the title in capitals
/// and a counter at the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.icon,
    required this.title,
    this.counter,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? counter;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final counter = this.counter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.04,
                  color: c.muted,
                ),
              ),
            ),
          ),
          if (counter != null)
            Text(
              counter,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// How much of the day is done (D22): a bar in the accent over the track and
/// "{done} of {total}" at the right; [label] is that text.
class DayProgress extends StatelessWidget {
  const DayProgress({
    required this.done,
    required this.total,
    required this.label,
    super.key,
  });

  final int done;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final share = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Semantics(
      value: label,
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: AppDims.progressHeight,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.track)),
                    AnimatedFractionallySizedBox(
                      duration: AppDims.progressAnim,
                      curve: Curves.easeOut,
                      widthFactor: share,
                      heightFactor: 1,
                      child: ColoredBox(color: c.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.title,
            ),
          ),
        ],
      ),
    );
  }
}

/// The body of a tab without an app bar (D22): below the status bar, so a
/// list that scrolls is cut off there and does not run under the clock.
class TabBody extends StatelessWidget {
  const TabBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(bottom: false, child: child);
}
