// Dump a PDF's glyph runs to JSON.
//
//   dart run pdf_glyph_source:dump_glyphs <input.pdf> <output.json> [password]
//
// The output is the parser's test corpus: statement_parser replays it with no
// PDF engine, no device and no bank document in the repo. Redact the `text`
// fields before committing anything derived from a real statement — keep the
// character count identical so the geometry still describes the same layout.

import 'dart:convert';
import 'dart:io';

import 'package:pdf_glyph_source/pdf_glyph_source.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run pdf_glyph_source:dump_glyphs '
      '<input.pdf> <output.json> [password]',
    );
    exitCode = 64;
    return;
  }

  final input = args[0];
  final output = args[1];
  final password = args.length > 2 ? args[2] : null;

  if (!File(input).existsSync()) {
    stderr.writeln('no such file: $input');
    exitCode = 66;
    return;
  }

  final started = DateTime.now();
  final source = PdfiumGlyphSource.file(input);
  final runs = await source.extract(password: password);
  final elapsed = DateTime.now().difference(started);

  final json = const JsonEncoder.withIndent('  ')
      .convert(runs.map((r) => r.toJson()).toList());
  File(output).writeAsStringSync(json);

  final pages = runs.isEmpty
      ? 0
      : runs.map((r) => r.pageIndex).reduce((a, b) => a > b ? a : b) + 1;

  stdout
    ..writeln('input   : $input')
    ..writeln('output  : $output')
    ..writeln('pages   : $pages')
    ..writeln('glyphs  : ${runs.length}')
    ..writeln('elapsed : ${elapsed.inMilliseconds} ms');
}
