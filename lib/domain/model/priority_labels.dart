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

  /// ARGB of the middle of every scale (amber).
  static const middleColor = 0xFFFFA000;

  /// ARGB of the last priority on every scale (grey).
  static const lowestColor = 0xFF9E9E9E;

  /// Every key [key] can return: 3 + 5 + 10 = 18.
  static List<String> get allKeys => [
    for (final scale in scales)
      for (var p = 1; p <= scale; p++) key(p, scale),
  ];

  /// Whether [scale] is supported and [priority] lies in `1..scale`.
  static bool isValid(int priority, int scale) =>
      scales.contains(scale) && priority >= 1 && priority <= scale;

  /// Localisation key of the label, for example `priority.s10.4`.
  ///
  /// Throws [ArgumentError] unless [isValid].
  static String key(int priority, int scale) {
    _check(priority, scale);
    return 'priority.s$scale.$priority';
  }

  /// Colour of the label as 0xAARRGGBB: a gradient from [highestColor]
  /// through [middleColor] to [lowestColor], shared by all scales.
  ///
  /// Throws [ArgumentError] unless [isValid].
  static int color(int priority, int scale) {
    _check(priority, scale);
    // Position on the gradient in half-steps: 0 = first, 2 * (scale - 1) = last,
    // scale - 1 = middle. Integers keep the anchors exact.
    final span = scale - 1;
    final position = 2 * (priority - 1);
    return position <= span
        ? _lerp(highestColor, middleColor, position, span)
        : _lerp(middleColor, lowestColor, position - span, span);
  }

  static void _check(int priority, int scale) {
    if (!scales.contains(scale)) {
      throw ArgumentError.value(scale, 'scale', 'Must be one of $scales');
    }
    if (priority < 1 || priority > scale) {
      throw ArgumentError.value(priority, 'priority', 'Must be in 1..$scale');
    }
  }

  /// Mixes two opaque colours channel by channel: [step] of [steps] from
  /// [from] to [to].
  static int _lerp(int from, int to, int step, int steps) {
    var result = 0xFF000000;
    for (final shift in const [16, 8, 0]) {
      final a = (from >> shift) & 0xFF;
      final b = (to >> shift) & 0xFF;
      final channel = a + ((b - a) * step / steps).round();
      result |= channel << shift;
    }
    return result;
  }
}
