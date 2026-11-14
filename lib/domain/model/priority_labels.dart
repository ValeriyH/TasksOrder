/// What a priority means and how it looks: its levels, label key and colour.
///
/// A priority is a fixed level of the ten-level table, 1 (highest) to 10
/// (lowest), whatever scale the user picked (D1, ADR-17). The scale (3, 5 or
/// 10) only chooses which levels the app offers: scale 5 is Critical (2),
/// High (3), Normal (5), Low (7), Someday (8); scale 3 is Critical, Normal,
/// Low. A task keeps its level when the scale changes; a level the scale does
/// not offer is shown as the nearest one it does.
///
/// The domain stays free of Flutter, so a label is a key the UI resolves
/// through its ARB files and a colour is a plain ARGB integer (ADR-11).
abstract final class PriorityLabels {
  /// Supported priority scales, see `Settings.priorityScale`.
  static const scales = [3, 5, 10];

  /// The highest level.
  static const highest = 1;

  /// The lowest level: the size of the full table.
  static const lowest = 10;

  /// "Normal": what a new task gets, on every scale.
  static const normal = 5;

  /// ARGB of the first level of every scale (red).
  static const highestColor = 0xFFD32F2F;

  /// ARGB halfway between the highest and the middle (orange): raised, asks
  /// for attention.
  static const raisedColor = 0xFFF57C00;

  /// ARGB of the middle of every scale (green): the ordinary level, which
  /// must not ask for attention.
  static const middleColor = 0xFF388E3C;

  /// ARGB halfway between the middle and the lowest (teal).
  static const loweredColor = 0xFF0097A7;

  /// ARGB of the last level of every scale (blue).
  static const lowestColor = 0xFF1976D2;

  static const _levels = {
    3: [2, 5, 7],
    5: [2, 3, 5, 7, 8],
    10: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  };

  /// The levels [scale] offers, highest first.
  ///
  /// Throws [ArgumentError] for an unsupported scale.
  static List<int> levels(int scale) {
    _checkScale(scale);
    return _levels[scale]!;
  }

  /// Every key [key] can return: 3 + 5 + 10 = 18.
  static List<String> get allKeys => [
    for (final scale in scales)
      for (final level in levels(scale)) key(level, scale),
  ];

  /// Whether [priority] is a level of the table, `1..10`.
  static bool isValid(int priority) =>
      priority >= highest && priority <= lowest;

  /// The level of [scale] that stands for [priority]: the nearest one, the
  /// higher of two at the same distance. A level of the scale is itself.
  static int nearest(int priority, int scale) =>
      levels(scale)[_index(priority, scale)];

  /// The level of [scale] that stood at [position] (1-based) in the old
  /// numbering, where a priority was `1..scale` (backup format 1, schema 1).
  /// A position past the end counts as the last level.
  static int fromPosition(int position, int scale) {
    final all = levels(scale);
    return all[(position < 1 ? 1 : position).clamp(1, all.length) - 1];
  }

  /// [priority] raised by [steps] levels of [scale] (urgency boost, D10):
  /// Normal on scale 5 with one step is High. Never lower than [priority]
  /// itself, never above the first level of the scale unless it already is.
  static int raise(int priority, int steps, int scale) {
    if (steps <= 0) return priority;
    final index = _index(priority, scale) - steps;
    final raised = levels(scale)[index < 0 ? 0 : index];
    return raised < priority ? raised : priority;
  }

  /// Localisation key of the label [priority] has on [scale], for example
  /// `priority.s5.3` for Normal (5) on scale 5: the position of its
  /// [nearest] level in the scale.
  ///
  /// Throws [ArgumentError] for an unsupported scale.
  static String key(int priority, int scale) =>
      'priority.s$scale.${_index(priority, scale) + 1}';

  /// Colour of [priority] on [scale] as 0xAARRGGBB: a gradient through five
  /// anchors, [highestColor] (red), [raisedColor] (orange), [middleColor]
  /// (green), [loweredColor] (teal) and [lowestColor] (blue), by the position
  /// of its [nearest] level in the scale. Scale 3 uses red, green, blue;
  /// scale 5 the five anchors themselves; scale 10 the steps between them.
  ///
  /// Throws [ArgumentError] for an unsupported scale.
  static int color(int priority, int scale) {
    const anchors = [
      highestColor,
      raisedColor,
      middleColor,
      loweredColor,
      lowestColor,
    ];
    // Position on the gradient in units of 1 / span of a segment: 0 = first
    // anchor, 4 * span = last. Integers keep the anchors exact.
    final span = levels(scale).length - 1;
    final position = (anchors.length - 1) * _index(priority, scale);
    final segment = position == (anchors.length - 1) * span
        ? anchors.length - 2
        : position ~/ span;
    return _lerp(
      anchors[segment],
      anchors[segment + 1],
      position - segment * span,
      span,
    );
  }

  /// Index in [levels] of the level nearest to [priority].
  static int _index(int priority, int scale) {
    final all = levels(scale);
    var best = 0;
    for (var i = 1; i < all.length; i++) {
      // Strictly nearer only: a tie keeps the higher level.
      if ((all[i] - priority).abs() < (all[best] - priority).abs()) best = i;
    }
    return best;
  }

  static void _checkScale(int scale) {
    if (!scales.contains(scale)) {
      throw ArgumentError.value(scale, 'scale', 'Must be one of $scales');
    }
  }

  /// Mixes two opaque colours: [step] of [steps] from [from] to [to], by
  /// hue, saturation and brightness, so that the steps between two anchors
  /// stay clear colours and do not turn brown or grey.
  static int _lerp(int from, int to, int step, int steps) {
    if (step == 0) return from;
    if (step == steps) return to;
    final a = _toHsv(from);
    final b = _toHsv(to);
    final t = step / steps;
    return _fromHsv(
      a.h + (b.h - a.h) * t,
      a.s + (b.s - a.s) * t,
      a.v + (b.v - a.v) * t,
    );
  }

  /// Hue in degrees (0 = red, 120 = green, 240 = blue), saturation and
  /// brightness in 0..1.
  static ({double h, double s, double v}) _toHsv(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255;
    final g = ((argb >> 8) & 0xFF) / 255;
    final b = (argb & 0xFF) / 255;
    final max = [r, g, b].reduce((x, y) => x > y ? x : y);
    final min = [r, g, b].reduce((x, y) => x < y ? x : y);
    final delta = max - min;
    var h = 0.0;
    if (delta > 0) {
      if (max == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60 * ((b - r) / delta + 2);
      } else {
        h = 60 * ((r - g) / delta + 4);
      }
    }
    return (h: h, s: max == 0 ? 0 : delta / max, v: max);
  }

  static int _fromHsv(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;
    final (r, g, b) = switch (h ~/ 60 % 6) {
      0 => (c, x, 0.0),
      1 => (x, c, 0.0),
      2 => (0.0, c, x),
      3 => (0.0, x, c),
      4 => (x, 0.0, c),
      _ => (c, 0.0, x),
    };
    int channel(double value) => ((value + m) * 255).round();
    return 0xFF000000 | channel(r) << 16 | channel(g) << 8 | channel(b);
  }
}
