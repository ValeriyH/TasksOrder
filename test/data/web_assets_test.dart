import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_assets.dart';

/// `web/drift_worker.js` and `web/sqlite3.wasm` are binaries built for exact
/// versions of `drift` and `sqlite3`. A package upgrade (Dependabot) does not
/// touch them, and the mismatch would show up only in the browser.
void main() {
  test('the web files of drift are present', () {
    expect(File('web/drift_worker.js').existsSync(), isTrue);
    // "\0asm": a WebAssembly module, not an error page saved by mistake.
    final header = File('web/sqlite3.wasm').readAsBytesSync().sublist(0, 4);
    expect(header, [0x00, 0x61, 0x73, 0x6d]);
  });

  test('they belong to the package versions in pubspec.lock', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final stamp = jsonDecode(File('web/drift_assets.json').readAsStringSync());

    expect(stamp, {
      'drift': lockedVersion(lock, 'drift'),
      'sqlite3': lockedVersion(lock, 'sqlite3'),
    }, reason: 'run "dart run tool/web_assets.dart" and commit web/');
  });
}
