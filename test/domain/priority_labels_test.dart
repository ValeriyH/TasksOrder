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

  group('color', () {
    test('endpoints are red and grey on every scale', () {
      for (final scale in PriorityLabels.scales) {
        expect(PriorityLabels.color(1, scale), PriorityLabels.highestColor);
        expect(PriorityLabels.color(scale, scale), PriorityLabels.lowestColor);
      }
    });

    test('the middle of an odd scale is amber', () {
      expect(PriorityLabels.color(2, 3), PriorityLabels.middleColor);
      expect(PriorityLabels.color(3, 5), PriorityLabels.middleColor);
    });

    test('anchor colours are opaque red, amber and grey', () {
      expect(PriorityLabels.highestColor, 0xFFD32F2F);
      expect(PriorityLabels.middleColor, 0xFFFFA000);
      expect(PriorityLabels.lowestColor, 0xFF9E9E9E);
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

    test('interpolates channel by channel between anchors', () {
      // Scale 5, priority 2: halfway from red D32F2F to amber FFA000.
      expect(PriorityLabels.color(2, 5), 0xFFE96817);
      // Scale 5, priority 4: halfway from amber FFA000 to grey 9E9E9E.
      expect(PriorityLabels.color(4, 5), 0xFFCE9F4F);
    });

    test('throws for a priority outside the scale or an unknown scale', () {
      expect(() => PriorityLabels.color(0, 5), throwsArgumentError);
      expect(() => PriorityLabels.color(11, 10), throwsArgumentError);
      expect(() => PriorityLabels.color(1, 7), throwsArgumentError);
    });
  });
}
