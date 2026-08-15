// Run the full pipeline over a glyph dump and check it against the
// statement's own arithmetic.
//
//   dart run statement_parser:extract_transactions <glyphs.json> [options]
//
//     --page=N       only this page (0-based)
//     --from-y=F     only rows at or below this y
//     --to-y=F       only rows at or above this y
//     --raw          print real descriptors instead of masked shapes
//
// Descriptions are masked by default. Dates, amounts and the reconciliation
// verdict are always shown in the clear — they are what tells you whether the
// parse is right, and the balance check is meaningless without them.

import 'dart:convert';
import 'dart:io';

import 'package:statement_parser/statement_parser.dart';

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'usage: dart run statement_parser:extract_transactions '
      '<glyphs.json> [--page=N] [--from-y=F] [--to-y=F] [--raw]',
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
  final fromY = double.tryParse(option('from-y') ?? '');
  final toY = double.tryParse(option('to-y') ?? '');
  final raw = args.contains('--raw');

  final runs = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
      .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);

  final rows = const RowClusterer().cluster(runs).where((row) {
    if (page != null && row.pageIndex != page) return false;
    if (fromY != null && row.centerY < fromY) return false;
    if (toY != null && row.centerY > toY) return false;
    return true;
  }).toList();

  final layout = const ColumnDetector().detect(rows);
  final extracted =
      const TableExtractor(TableSchema.bankPassbook).extract(rows, layout);

  stdout
    ..writeln('rows in       : ${rows.length}')
    ..writeln('layout        : $layout')
    ..writeln('transactions  : ${extracted.length}')
    ..writeln();

  for (final row in extracted) {
    final description = raw
        ? row.transaction.description
        : maskStructure(row.transaction.description);
    final trimmed =
        description.length > 46 ? description.substring(0, 46) : description;
    stdout.writeln(
      '${formatIsoDate(row.transaction.date)}  '
      '${row.transaction.amount.toDecimalString().padLeft(11)}  '
      'bal ${(row.balance?.toDecimalString() ?? "—").padLeft(11)}  '
      '$trimmed',
    );
  }

  final check = reconcileRunningBalance(extracted);
  stdout
    ..writeln()
    ..writeln('--- balance reconciliation ---')
    ..writeln('checked rows  : ${check.checkedRows}')
    ..writeln('mismatches    : ${check.mismatches.length}')
    ..writeln(
      'consistency   : ${(check.consistency * 100).toStringAsFixed(1)}%',
    );

  for (final mismatch in check.mismatches.take(10)) {
    // Never interpolate the mismatch directly: its toString carries the raw
    // descriptor, and this line is the one most likely to get pasted into an
    // issue or a chat window.
    final description = raw
        ? mismatch.row.transaction.description
        : maskStructure(mismatch.row.transaction.description);
    stdout.writeln(
      '  row ${mismatch.index}: expected '
      '${mismatch.expected.toDecimalString()}, statement says '
      '${mismatch.actual.toDecimalString()} '
      '(off by ${mismatch.drift.toDecimalString()})  $description',
    );
  }

  if (!check.isConsistent) exitCode = 1;
}
