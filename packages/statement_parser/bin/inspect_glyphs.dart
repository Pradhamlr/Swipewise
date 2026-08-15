// Inspect a glyph dump: cluster it into rows and print the page's structure.
//
//   dart run statement_parser:inspect_glyphs <glyphs.json> [options]
//
//     --page=N        only this page (0-based)
//     --rows=N        stop after N rows (default 60)
//     --tolerance=F   row clustering tolerance factor (default 0.6)
//     --from-y=F      only rows whose centre is at or below this y
//     --to-y=F        only rows whose centre is at or above this y
//     --columns       detect column boundaries over the selected rows and
//                     print each row split into cells
//     --raw           print real text instead of masked shapes
//
// The y filters exist because column detection wants the table body only.
// Headers and footers span different x ranges and erode the very whitespace
// bands the detector is looking for.
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

  final fromY = double.tryParse(option('from-y') ?? '');
  final toY = double.tryParse(option('to-y') ?? '');

  final selected = rows.where((row) {
    if (page != null && row.pageIndex != page) return false;
    if (fromY != null && row.centerY < fromY) return false;
    if (toY != null && row.centerY > toY) return false;
    return true;
  }).toList();

  stdout
    ..writeln('rows     : ${selected.length}'
        '${page == null ? " (all pages)" : " (page $page)"}')
    ..writeln();

  String show(String value) => raw ? value : maskStructure(value);

  if (args.contains('--columns')) {
    final layout = const ColumnDetector().detect(selected);
    stdout
      ..writeln(layout)
      ..writeln();

    for (final row in selected.take(rowLimit)) {
      final cells = layout.cells(row);
      final rendered = [
        for (final cell in cells)
          if (cell == null) '·' else show(cell.text),
      ];
      stdout.writeln(
        'y=${row.centerY.toStringAsFixed(1).padLeft(6)} | '
        '${rendered.join("  ¦  ")}',
      );
    }
    return;
  }

  final width = _terminalWidth();
  for (final row in selected.take(rowLimit)) {
    final text = show(row.text);
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
