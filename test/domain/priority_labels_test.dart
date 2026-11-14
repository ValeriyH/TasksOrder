import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';

void main() {
  group('levels (ADR-17)', () {
    test('scales are 3, 5 and 10', () {
      expect(PriorityLabels.scales, [3, 5, 10]);
    });

    test('each scale offers fixed levels of the ten-level table', () {
      expect(PriorityLabels.levels(3), [2, 5, 7]);
      expect(PriorityLabels.levels(5), [2, 3, 5, 7, 8]);
      expect(PriorityLabels.levels(10), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('Normal is 5 and every scale offers it', () {
      expect(PriorityLabels.normal, 5);
      for (final scale in PriorityLabels.scales) {
        expect(PriorityLabels.levels(scale), contains(PriorityLabels.normal));
      }
    });

    test('a level keeps its name on every scale that offers it', () {
      // Critical, Normal and Low are the same levels on 3, 5 and 10; High and
      // Someday on 5 and 10.
      expect(PriorityLabels.key(2, 3), 'priority.s3.1');
      expect(PriorityLabels.key(2, 5), 'priority.s5.1');
      expect(PriorityLabels.key(2, 10), 'priority.s10.2');
      expect(PriorityLabels.key(5, 3), 'priority.s3.2');
      expect(PriorityLabels.key(5, 5), 'priority.s5.3');
      expect(PriorityLabels.key(5, 10), 'priority.s10.5');
      expect(PriorityLabels.key(7, 3), 'priority.s3.3');
      expect(PriorityLabels.key(7, 5), 'priority.s5.4');
      expect(PriorityLabels.key(7, 10), 'priority.s10.7');
      expect(PriorityLabels.key(3, 5), 'priority.s5.2');
      expect(PriorityLabels.key(8, 5), 'priority.s5.5');
    });

    test('throws for an unknown scale', () {
      expect(() => PriorityLabels.levels(4), throwsArgumentError);
      expect(() => PriorityLabels.key(5, 7), throwsArgumentError);
      expect(() => PriorityLabels.color(5, 1), throwsArgumentError);
    });
  });

  group('isValid', () {
    test('accepts the levels 1..10 only', () {
      for (var p = 1; p <= 10; p++) {
        expect(PriorityLabels.isValid(p), isTrue, reason: '$p');
      }
      expect(PriorityLabels.isValid(0), isFalse);
      expect(PriorityLabels.isValid(-1), isFalse);
      expect(PriorityLabels.isValid(11), isFalse);
    });
  });

  group('nearest', () {
    List<int> all(int scale) => [
      for (var p = 1; p <= 10; p++) PriorityLabels.nearest(p, scale),
    ];

    test('a level of the scale is itself', () {
      for (final scale in PriorityLabels.scales) {
        for (final level in PriorityLabels.levels(scale)) {
          expect(PriorityLabels.nearest(level, scale), level);
        }
      }
    });

    test('the other levels show as the nearest, the higher on a tie', () {
      expect(all(5), [2, 2, 3, 3, 5, 5, 7, 8, 8, 8]);
      expect(all(3), [2, 2, 2, 5, 5, 5, 7, 7, 7, 7]);
      expect(all(10), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    test('keeps the order of the tasks', () {
      for (final scale in PriorityLabels.scales) {
        final shown = all(scale);
        for (var i = 1; i < shown.length; i++) {
          expect(shown[i], greaterThanOrEqualTo(shown[i - 1]));
        }
      }
    });
  });

  group('fromPosition (format 1)', () {
    test('the n-th level of the old scale', () {
      expect(
        [for (var p = 1; p <= 5; p++) PriorityLabels.fromPosition(p, 5)],
        [2, 3, 5, 7, 8],
      );
      expect(
        [for (var p = 1; p <= 3; p++) PriorityLabels.fromPosition(p, 3)],
        [2, 5, 7],
      );
      expect(
        [for (var p = 1; p <= 10; p++) PriorityLabels.fromPosition(p, 10)],
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
    });

    test('keeps the name a task had: the middle of each scale is Normal', () {
      expect(PriorityLabels.fromPosition(2, 3), PriorityLabels.normal);
      expect(PriorityLabels.fromPosition(3, 5), PriorityLabels.normal);
      expect(PriorityLabels.fromPosition(5, 10), PriorityLabels.normal);
    });

    test('a value past either end is the end', () {
      expect(PriorityLabels.fromPosition(9, 5), 8);
      expect(PriorityLabels.fromPosition(4, 3), 7);
      expect(PriorityLabels.fromPosition(0, 5), 2);
    });
  });

  group('raise (urgency boost, D10)', () {
    test('steps are levels of the scale', () {
      expect(PriorityLabels.raise(5, 1, 5), 3); // Normal -> High
      expect(PriorityLabels.raise(5, 2, 5), 2); // Normal -> Critical
      expect(PriorityLabels.raise(7, 1, 3), 5); // Low -> Normal
      expect(PriorityLabels.raise(5, 1, 10), 4); // Normal -> Elevated
      expect(PriorityLabels.raise(5, 2, 10), 3); // Normal -> High
    });

    test('no step keeps the priority', () {
      for (var p = 1; p <= 10; p++) {
        expect(PriorityLabels.raise(p, 0, 5), p);
      }
    });

    test('stops at the first level of the scale', () {
      expect(PriorityLabels.raise(3, 2, 5), 2);
      expect(PriorityLabels.raise(2, 1, 3), 2);
      expect(PriorityLabels.raise(2, 2, 10), 1);
    });

    test('never lowers a level the scale does not offer', () {
      // Catastrophic (1) on scale 5 shows as Critical (2) but stays 1.
      expect(PriorityLabels.raise(1, 1, 5), 1);
      // Elevated (4) shows as High on scale 5: one step is Critical.
      expect(PriorityLabels.raise(4, 1, 5), 2);
    });
  });

  group('key', () {
    test('every scale has one key per level, in order', () {
      expect(
        [for (final p in PriorityLabels.levels(3)) PriorityLabels.key(p, 3)],
        ['priority.s3.1', 'priority.s3.2', 'priority.s3.3'],
      );
      expect(
        [for (final p in PriorityLabels.levels(5)) PriorityLabels.key(p, 5)],
        [
          'priority.s5.1',
          'priority.s5.2',
          'priority.s5.3',
          'priority.s5.4',
          'priority.s5.5',
        ],
      );
      expect(
        [for (var p = 1; p <= 10; p++) PriorityLabels.key(p, 10)],
        [for (var p = 1; p <= 10; p++) 'priority.s10.$p'],
      );
    });

    test('a level the scale does not offer has the key of the nearest', () {
      expect(PriorityLabels.key(4, 5), PriorityLabels.key(3, 5));
      expect(PriorityLabels.key(10, 5), PriorityLabels.key(8, 5));
      expect(PriorityLabels.key(1, 3), PriorityLabels.key(2, 3));
    });

    test('all 18 keys are distinct and listed by allKeys', () {
      final keys = {
        for (final scale in PriorityLabels.scales)
          for (var p = 1; p <= 10; p++) PriorityLabels.key(p, scale),
      };
      expect(keys, hasLength(18));
      expect(PriorityLabels.allKeys.toSet(), keys);
      expect(PriorityLabels.allKeys, hasLength(18));
    });
  });

  group('color', () {
    List<int> ofLevels(int scale) => [
      for (final p in PriorityLabels.levels(scale))
        PriorityLabels.color(p, scale),
    ];

    test('the first and last level of every scale are red and blue', () {
      for (final scale in PriorityLabels.scales) {
        final colors = ofLevels(scale);
        expect(colors.first, PriorityLabels.highestColor);
        expect(colors.last, PriorityLabels.lowestColor);
      }
    });

    test('Normal is green on scales 3 and 5', () {
      expect(PriorityLabels.color(5, 3), PriorityLabels.middleColor);
      expect(PriorityLabels.color(5, 5), PriorityLabels.middleColor);
    });

    test('anchor colours are opaque red, green and blue', () {
      expect(PriorityLabels.highestColor, 0xFFD32F2F);
      expect(PriorityLabels.middleColor, 0xFF388E3C);
      expect(PriorityLabels.lowestColor, 0xFF1976D2);
    });

    test('every colour is opaque and unique within its scale', () {
      for (final scale in PriorityLabels.scales) {
        final colors = ofLevels(scale);
        for (final c in colors) {
          expect(c >> 24, 0xFF, reason: c.toRadixString(16));
        }
        expect(colors.toSet(), hasLength(colors.length));
      }
    });

    test('scale 5 is the five anchors: red, orange, green, teal, blue', () {
      expect(ofLevels(5), [
        PriorityLabels.highestColor,
        PriorityLabels.raisedColor,
        PriorityLabels.middleColor,
        PriorityLabels.loweredColor,
        PriorityLabels.lowestColor,
      ]);
      expect(PriorityLabels.raisedColor, 0xFFF57C00);
      expect(PriorityLabels.loweredColor, 0xFF0097A7);
    });

    test('scale 10 runs through the steps between the anchors', () {
      expect(ofLevels(10), [
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
      ]);
    });

    test('a level the scale does not offer has the colour of the nearest', () {
      expect(PriorityLabels.color(4, 5), PriorityLabels.color(3, 5));
      expect(PriorityLabels.color(9, 3), PriorityLabels.lowestColor);
    });
  });
}
