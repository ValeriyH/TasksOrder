// Puts the files drift needs in the browser into web/ (T-206):
//   web/drift_worker.js   copied from the resolved `drift` package
//   web/sqlite3.wasm      downloaded from the `sqlite3` GitHub release
//   web/drift_assets.json the package versions the two files belong to
//
// Both files must match the package versions in pubspec.lock, so run this
// after every upgrade of `drift` or `sqlite3`:
//   dart run tool/web_assets.dart
// test/data/web_assets_test.dart fails while the files are out of date.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final root = Directory.current;
  if (!File('${root.path}/pubspec.lock').existsSync()) {
    stderr.writeln('Run from the project root: dart run tool/web_assets.dart');
    exit(2);
  }
  final lock = File('${root.path}/pubspec.lock').readAsStringSync();
  final driftVersion = lockedVersion(lock, 'drift');
  final sqliteVersion = lockedVersion(lock, 'sqlite3');

  final worker = File('${packageRoot(root, 'drift')}/drift_worker.js');
  if (!worker.existsSync()) {
    stderr.writeln('No drift_worker.js in drift $driftVersion: ${worker.path}');
    exit(1);
  }
  worker.copySync('${root.path}/web/drift_worker.js');
  stdout.writeln('web/drift_worker.js  <- drift $driftVersion');

  final url = Uri.parse(
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    'sqlite3-$sqliteVersion/sqlite3.wasm',
  );
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln('GET $url: HTTP ${response.statusCode}');
      exit(1);
    }
    await response.pipe(File('${root.path}/web/sqlite3.wasm').openWrite());
  } finally {
    client.close();
  }
  stdout.writeln('web/sqlite3.wasm     <- sqlite3 $sqliteVersion');

  File('${root.path}/web/drift_assets.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'drift': driftVersion, 'sqlite3': sqliteVersion})}\n',
  );
}

/// The version of [package] in the text of a pubspec.lock.
String lockedVersion(String lock, String package) {
  final match = RegExp(
    '^  $package:\\r?\\n(?:    .*\\r?\\n)*?    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock);
  if (match == null) throw StateError('$package is not in pubspec.lock');
  return match.group(1)!;
}

/// The directory of [package] as resolved by `pub get`.
String packageRoot(Directory root, String package) {
  final config = jsonDecode(
    File('${root.path}/.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final entry = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => entry['name'] == package);
  return Uri.parse(entry['rootUri'] as String).toFilePath();
}
