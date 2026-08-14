// Inspect a glyph dump: cluster it into rows and print the page's structure.
//
//   dart run statement_parser:inspect_glyphs <glyphs.json> [options]
//
//     --page=N        only this page (0-based)
//     --rows=N        stop after N rows (default 60)
//     --tolerance=F   row clustering tolerance factor (default 0.6)
//     --raw           print real text instead of masked shapes
//
// Output is masked by default: letters become A/a and digits 9, so layout can
// be read and discussed without disclosing merchants, names or amounts. Pass
// --raw only when looking at your own screen.

import 'dart:convert';
import 'dart:io';

import 'package:statement_parser/statement_parser.dart';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run statement_parser:inspect_glyphs <glyphs.json> '
      '[--page=N] [--rows=N] [--tolerance=F] [--raw]',
    );
    exitCode = 64;
    return;
  }

  String? option(String name) {
    final prefix = '--$name=';
    for (final arg in args) {
      if (arg.startsWith(prefix)) return arg.substring(prefix.length);
    }
    return null;
  }

  final file = File(positional.first);
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${positional.first}');
    exitCode = 66;
    return;
  }

  final page = int.tryParse(option('page') ?? '');
  final rowLimit = int.tryParse(option('rows') ?? '') ?? 60;
  final tolerance = double.tryParse(option('tolerance') ?? '') ?? 0.6;
  final raw = args.contains('--raw');

  final decoded = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final runs = decoded
      .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final pages = runs.map((r) => r.pageIndex).toSet().toList()..sort();
  stdout
    ..writeln('glyphs   : ${runs.length}')
    ..writeln('pages    : ${pages.length}')
    ..writeln('tolerance: $tolerance')
    ..writeln('masked   : ${!raw}')
    ..writeln();

  final rows = RowClusterer(toleranceFactor: tolerance).cluster(runs);

  final selected =
      page == null ? rows : rows.where((r) => r.pageIndex == page).toList();

  stdout
    ..writeln('rows     : ${selected.length}'
        '${page == null ? " (all pages)" : " (page $page)"}')
    ..writeln();

  final width = _terminalWidth();
  for (final row in selected.take(rowLimit)) {
    final text = raw ? row.text : maskStructure(row.text);
    final head = 'p${row.pageIndex} '
        'y=${row.centerY.toStringAsFixed(1).padLeft(6)} '
        'x=[${row.left.toStringAsFixed(0).padLeft(3)},'
        '${row.right.toStringAsFixed(0).padLeft(3)}] '
        'n=${row.glyphs.length.toString().padLeft(3)} | ';
    final room = width - head.length;
    final body = text.length > room && room > 3
        ? '${text.substring(0, room - 1)}…'
        : text;
    stdout.writeln('$head$body');
  }

  if (selected.length > rowLimit) {
    stdout.writeln('... ${selected.length - rowLimit} more rows');
  }
}

int _terminalWidth() {
  try {
    final width = stdout.terminalColumns;
    return width > 40 ? width : 120;
  } on StdoutException {
    return 120;
  }
}
