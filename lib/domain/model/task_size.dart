/// The named sizes of a task (D21, ADR-19): how much of a day it takes, in
/// half-slots of the daily capacity. A task stores its weight, not the
/// size, so a later change of the sizes touches no task; these names are
/// for the UI.
enum TaskSize {
  /// Half a slot: two of them fit where one normal task does.
  small(1),

  /// One slot: what "tasks per day" counts.
  normal(2),

  /// Two slots: waits for a day with room for it.
  large(4);

  const TaskSize(this.weight);

  /// The weight of the size in half-slots.
  final int weight;

  /// The weight of a new task.
  static const defaultWeight = 2;

  /// The size a stored [weight] reads as: the nearest one, the larger on a
  /// tie (3 reads as large), as a priority level the scale does not offer
  /// reads as the nearest level (ADR-17). The weight itself stays stored.
  static TaskSize nearest(int weight) {
    var best = TaskSize.small;
    for (final size in TaskSize.values) {
      final distance = (size.weight - weight).abs();
      final bestDistance = (best.weight - weight).abs();
      if (distance <= bestDistance) best = size;
    }
    return best;
  }
}
