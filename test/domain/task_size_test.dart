import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_order/domain/model/task_size.dart';

void main() {
  test('the sizes weigh 1, 2 and 4 half-slots (D21)', () {
    expect(TaskSize.small.weight, 1);
    expect(TaskSize.normal.weight, 2);
    expect(TaskSize.large.weight, 4);
    expect(TaskSize.defaultWeight, TaskSize.normal.weight);
  });

  group('nearest (ADR-19)', () {
    test('a named weight reads as its size', () {
      for (final size in TaskSize.values) {
        expect(TaskSize.nearest(size.weight), size);
      }
    });

    test(
      'an unknown weight reads as the nearest size, the larger on a tie',
      () {
        expect(TaskSize.nearest(3), TaskSize.large);
        expect(TaskSize.nearest(5), TaskSize.large);
        expect(TaskSize.nearest(40), TaskSize.large);
      },
    );

    test('below the smallest it reads as small', () {
      expect(TaskSize.nearest(0), TaskSize.small);
      expect(TaskSize.nearest(-1), TaskSize.small);
    });
  });
}
