// Enforces the load-bearing architectural boundary: the engine packages must
// have zero Flutter dependencies, so they run on CI without a device and stay
// usable from a plain `dart test`.
//
// pdf_glyph_source is on this list even though it reaches native code — it
// binds PDFium through dart:ffi via pdfrx_engine, which is Flutter-free. That
// is the whole reason the parse pipeline needs no emulator.
//
// Run: dart run tools/check_purity.dart   (or: melos run check:purity)

import 'dart:io';

import 'package:yaml/yaml.dart';

const _purePackages = <String>[
  'packages/rewards_engine',
  'packages/statement_parser',
  'packages/pdf_glyph_source',
];

const _bannedDependencies = <String>{
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_driver',
  'integration_test',
};

const _bannedImports = <String>[
  'package:flutter/',
  'package:flutter_test/',
  'dart:ui',
];

void main() {
  final violations = <String>[];

  for (final package in _purePackages) {
    final pubspec = File('$package/pubspec.yaml');
    if (!pubspec.existsSync()) {
      violations.add('$package: pubspec.yaml is missing');
      continue;
    }

    final doc = loadYaml(pubspec.readAsStringSync());
    if (doc is YamlMap) {
      for (final section in const [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides',
      ]) {
        final deps = doc[section];
        if (deps is! YamlMap) continue;
        for (final name in deps.keys) {
          if (_bannedDependencies.contains(name)) {
            violations.add('$package: $section contains "$name"');
          }
        }
      }
    }

    final dir = Directory(package);
    final dartFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.startsWith('import ') && !line.startsWith('export ')) {
          continue;
        }
        for (final banned in _bannedImports) {
          if (line.contains(banned)) {
            violations.add(
              '${file.path}:${i + 1}: imports "$banned"',
            );
          }
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('purity OK: ${_purePackages.join(', ')} are Flutter-free');
    return;
  }

  stderr.writeln('Pure-Dart boundary violated:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  exitCode = 1;
}
