/// Presentation metadata for a priority: its localisation key and colour.
///
/// Priority 1 is the highest; the scale (3, 5 or 10) is the lowest value (D1).
/// The domain stays free of Flutter, so a label is a key the UI resolves
/// through its ARB files and a colour is a plain ARGB integer (ADR-11).
abstract final class PriorityLabels {
  /// Supported priority scales, see `Settings.priorityScale`.
  static const scales = [3, 5, 10];

  /// ARGB of priority 1 on every scale (red).
  static const highestColor = 0xFFD32F2F;

  /// ARGB halfway between the highest and the middle (orange): raised, asks
  /// for attention.
  static const raisedColor = 0xFFF57C00;

  /// ARGB of the middle of every scale (green): the ordinary level, which
  /// must not ask for attention.
  static const middleColor = 0xFF388E3C;

  /// ARGB halfway between the middle and the lowest (teal).
  static const loweredColor = 0xFF0097A7;

  /// ARGB of the last priority on every scale (blue).
  static const lowestColor = 0xFF1976D2;

  /// Every key [key] can return: 3 + 5 + 10 = 18.
  static List<String> get allKeys => [
    for (final scale in scales)
      for (var p = 1; p <= scale; p++) key(p, scale),
  ];

  /// Whether [scale] is supported and [priority] lies in `1..scale`.
  static bool isValid(int priority, int scale) =>
      scales.contains(scale) && priority >= 1 && priority <= scale;

  /// The priority a task gets when the scale changes [from] one size [to]
  /// another (T-406). A bigger scale keeps the value: 1..3 is valid inside
  /// 1..10 (D1). A smaller one squeezes the levels in proportion, rounding
  /// towards the lower priority, so 10 to 5 is `ceil(p / 2)` and the order of
  /// the tasks is kept. A value above [from] counts as the last level.
  static int remap(int priority, {required int from, required int to}) {
    if (to >= from) return priority;
    final clamped = priority > from ? from : priority;
    // ceil(clamped * to / from) in integers.
    return (clamped * to + from - 1) ~/ from;
  }

  /// Localisation key of the label, for example `priority.s10.4`.
  ///
  /// Throws [ArgumentError] unless [isValid].
  static String key(int priority, int scale) {
    _check(priority, scale);
    return 'priority.s$scale.$priority';
  }

  /// Colour of the label as 0xAARRGGBB, shared by all scales: a gradient
  /// through five anchors, [highestColor] (red), [raisedColor] (orange),
  /// [middleColor] (green), [loweredColor] (teal) and [lowestColor] (blue).
  /// Scale 3 uses red, green, blue; scale 5 the five anchors themselves;
  /// scale 10 the steps between them.
  ///
  /// Throws [ArgumentError] unless [isValid].
  static int color(int priority, int scale) {
    _check(priority, scale);
    const anchors = [
      highestColor,
      raisedColor,
      middleColor,
      loweredColor,
      lowestColor,
    ];
    // Position on the gradient in units of 1 / span of a segment: 0 = first
    // anchor, 4 * span = last. Integers keep the anchors exact.
    final span = scale - 1;
    final position = (anchors.length - 1) * (priority - 1);
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

  static void _check(int priority, int scale) {
    if (!scales.contains(scale)) {
      throw ArgumentError.value(scale, 'scale', 'Must be one of $scales');
    }
    if (priority < 1 || priority > scale) {
      throw ArgumentError.value(priority, 'priority', 'Must be in 1..$scale');
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
