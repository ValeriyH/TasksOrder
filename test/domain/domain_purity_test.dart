import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the architecture rule from docs/02 Architecture.md:
/// `lib/domain` must not import Flutter or drift.
void main() {
  test('lib/domain has no Flutter or drift imports', () {
    final forbidden = RegExp(
      r'''^\s*(import|export)\s+['"]package:(flutter|flutter_riverpod|material_ui|drift|sqlite3)[/_]''',
      multiLine: true,
    );
    final offenders = Directory('lib/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => forbidden.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty, reason: 'domain must stay pure Dart');
  });
}
