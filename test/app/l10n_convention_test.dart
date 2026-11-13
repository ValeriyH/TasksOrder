import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Conventions of T-301: every text the user sees comes from the ARB files,
/// and both languages have the same messages.
void main() {
  test('no string literals in widgets', () {
    // Text('...') and the usual named text arguments with a literal.
    final literal = RegExp(
      r'''(\bText\(\s*|\b(label|labelText|hintText|helperText|tooltip|title|message|semanticLabel|semanticsLabel):\s*)r?['"]''',
    );
    final offenders = <String>[];
    for (final dir in ['lib/app', 'lib/features', 'lib/shared']) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'),
          );
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (literal.hasMatch(line)) offenders.add('${file.path}:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty, reason: 'use context.l10n and lib/l10n/*.arb');
  });

  test('en and uk have the same messages', () {
    Set<String> keys(String path) => {
      for (final key in (jsonDecode(
        File(path).readAsStringSync(),
      ) as Map<String, dynamic>).keys)
        if (!key.startsWith('@')) key,
    };

    expect(keys('lib/l10n/app_uk.arb'), keys('lib/l10n/app_en.arb'));
  });
}
