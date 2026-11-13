import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';

void main() {
  group('isValid', () {
    test('accepts 1..scale on every supported scale', () {
      for (final scale in PriorityLabels.scales) {
        for (var p = 1; p <= scale; p++) {
          expect(PriorityLabels.isValid(p, scale), isTrue, reason: '$p/$scale');
        }
        expect(PriorityLabels.isValid(0, scale), isFalse);
        expect(PriorityLabels.isValid(-1, scale), isFalse);
        expect(PriorityLabels.isValid(scale + 1, scale), isFalse);
      }
    });

    test('rejects unsupported scales', () {
      for (final scale in [0, 1, 4, 7, 11]) {
        expect(PriorityLabels.isValid(1, scale), isFalse, reason: '$scale');
      }
    });
  });

  group('key', () {
    test('scales are 3, 5 and 10', () {
      expect(PriorityLabels.scales, [3, 5, 10]);
    });

    test('scale 3 has 3 keys', () {
      expect(
        [for (var p = 1; p <= 3; p++) PriorityLabels.key(p, 3)],
        ['priority.s3.1', 'priority.s3.2', 'priority.s3.3'],
      );
    });

    test('scale 5 has 5 keys', () {
      expect(
        [for (var p = 1; p <= 5; p++) PriorityLabels.key(p, 5)],
        [
          'priority.s5.1',
          'priority.s5.2',
          'priority.s5.3',
          'priority.s5.4',
          'priority.s5.5',
        ],
      );
    });

    test('scale 10 has 10 keys', () {
      expect(
        [for (var p = 1; p <= 10; p++) PriorityLabels.key(p, 10)],
        [
          'priority.s10.1',
          'priority.s10.2',
          'priority.s10.3',
          'priority.s10.4',
          'priority.s10.5',
          'priority.s10.6',
          'priority.s10.7',
          'priority.s10.8',
          'priority.s10.9',
          'priority.s10.10',
        ],
      );
    });

    test('all 18 keys are distinct and listed by allKeys', () {
      final keys = {
        for (final scale in PriorityLabels.scales)
          for (var p = 1; p <= scale; p++) PriorityLabels.key(p, scale),
      };
      expect(keys, hasLength(18));
      expect(PriorityLabels.allKeys.toSet(), keys);
      expect(PriorityLabels.allKeys, hasLength(18));
    });

    test('throws for a priority outside the scale or an unknown scale', () {
      expect(() => PriorityLabels.key(0, 5), throwsArgumentError);
      expect(() => PriorityLabels.key(6, 5), throwsArgumentError);
      expect(() => PriorityLabels.key(4, 3), throwsArgumentError);
      expect(() => PriorityLabels.key(1, 4), throwsArgumentError);
    });
  });

  group('remap (T-406)', () {
    List<int> all(int from, int to) => [
      for (var p = 1; p <= from; p++)
        PriorityLabels.remap(p, from: from, to: to),
    ];

    test('10 to 5 halves, rounding to the lower priority', () {
      expect(all(10, 5), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    });

    test('10 to 3 and 5 to 3 squeeze in proportion', () {
      expect(all(10, 3), [1, 1, 1, 2, 2, 2, 3, 3, 3, 3]);
      expect(all(5, 3), [1, 2, 2, 3, 3]);
    });

    test('a bigger or equal scale keeps the values', () {
      expect(all(3, 10), [1, 2, 3]);
      expect(all(5, 10), [1, 2, 3, 4, 5]);
      expect(all(5, 5), [1, 2, 3, 4, 5]);
    });

    test('the order of the tasks is kept and the ends stay the ends', () {
      for (final (from, to) in [(10, 5), (10, 3), (5, 3)]) {
        final mapped = all(from, to);
        expect(mapped.first, 1);
        expect(mapped.last, to);
        for (var i = 1; i < mapped.length; i++) {
          expect(mapped[i], greaterThanOrEqualTo(mapped[i - 1]));
        }
      }
    });

    test('a value above the old scale becomes the last level', () {
      expect(PriorityLabels.remap(9, from: 5, to: 3), 3);
    });
  });

  group('color', () {
    test('endpoints are red and blue on every scale', () {
      for (final scale in PriorityLabels.scales) {
        expect(PriorityLabels.color(1, scale), PriorityLabels.highestColor);
        expect(PriorityLabels.color(scale, scale), PriorityLabels.lowestColor);
      }
    });

    test('the middle of an odd scale is green', () {
      expect(PriorityLabels.color(2, 3), PriorityLabels.middleColor);
      expect(PriorityLabels.color(3, 5), PriorityLabels.middleColor);
    });

    test('anchor colours are opaque red, green and blue', () {
      expect(PriorityLabels.highestColor, 0xFFD32F2F);
      expect(PriorityLabels.middleColor, 0xFF388E3C);
      expect(PriorityLabels.lowestColor, 0xFF1976D2);
    });

    test('every colour is opaque and unique within its scale', () {
      for (final scale in PriorityLabels.scales) {
        final colors = [
          for (var p = 1; p <= scale; p++) PriorityLabels.color(p, scale),
        ];
        for (final c in colors) {
          expect(c >> 24, 0xFF, reason: c.toRadixString(16));
        }
        expect(colors.toSet(), hasLength(scale));
      }
    });

    test('scale 5 is the five anchors: red, orange, green, teal, blue', () {
      expect(
        [for (var p = 1; p <= 5; p++) PriorityLabels.color(p, 5)],
        [
          PriorityLabels.highestColor,
          PriorityLabels.raisedColor,
          PriorityLabels.middleColor,
          PriorityLabels.loweredColor,
          PriorityLabels.lowestColor,
        ],
      );
      expect(PriorityLabels.raisedColor, 0xFFF57C00);
      expect(PriorityLabels.loweredColor, 0xFF0097A7);
    });

    test('scale 10 runs through the steps between the anchors', () {
      expect(
        [for (var p = 1; p <= 10; p++) PriorityLabels.color(p, 10)],
        [
          0xFFD32F2F,
          0xFFE2491C,
          0xFFF17006,
          0xFFCFD31C,
          0xFF54A533,
          0xFF2D944A,
          0xFF159F7C,
          0xFF0294AC,
          0xFF0D86BF,
          0xFF1976D2,
        ],
      );
    });

    test('throws for a priority outside the scale or an unknown scale', () {
      expect(() => PriorityLabels.color(0, 5), throwsArgumentError);
      expect(() => PriorityLabels.color(11, 10), throwsArgumentError);
      expect(() => PriorityLabels.color(1, 7), throwsArgumentError);
    });
  });
}
