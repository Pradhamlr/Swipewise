// Run the full pipeline over one or more glyph dumps and check each result
// against the statement's own running balance.
//
//   dart run statement_parser:extract_transactions <glyphs.json> [more...]
//
//     --raw        print real descriptors instead of masked shapes
//     --summary    per-file totals only, no transaction listing
//
// Tables are located automatically — no page or y-range arguments. Anything
// that is not a run of dated rows is not a table.

import 'dart:convert';
import 'dart:io';

import 'package:statement_parser/statement_parser.dart';

void main(List<String> args) {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.isEmpty) {
    stderr.writeln(
      'usage: dart run statement_parser:extract_transactions '
      '<glyphs.json> [more...] [--raw] [--summary]',
    );
    exitCode = 64;
    return;
  }

  final raw = args.contains('--raw');
  final summaryOnly = args.contains('--summary');

  var totalTransactions = 0;
  var totalChecked = 0;
  var totalMismatches = 0;

  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('no such file: $path');
      exitCode = 66;
      continue;
    }

    final runs = (jsonDecode(file.readAsStringSync()) as List<dynamic>)
        .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    final rows = const RowClusterer().cluster(runs);
    final regions = const TableLocator().locate(rows);

    final extracted = <ExtractedRow>[];
    for (final region in regions) {
      final layout = const ColumnDetector().detect(region.anchorRows);
      extracted.addAll(
        const TableExtractor(TableSchema.bankPassbook)
            .extract(region.rows, layout),
      );
    }

    final check = reconcileRunningBalance(extracted);
    totalTransactions += extracted.length;
    totalChecked += check.checkedRows;
    totalMismatches += check.mismatches.length;

    final name = path.split(RegExp(r'[/\\]')).last;
    stdout.writeln(
      '${name.padRight(14)} '
      'glyphs ${runs.length.toString().padLeft(6)}  '
      'rows ${rows.length.toString().padLeft(4)}  '
      'tables ${regions.length}  '
      'txns ${extracted.length.toString().padLeft(4)}  '
      'checked ${check.checkedRows.toString().padLeft(4)}  '
      'consistency ${(check.consistency * 100).toStringAsFixed(1).padLeft(5)}%',
    );

    if (!summaryOnly) {
      for (final region in regions) {
        stdout.writeln('  $region');
      }
      for (final row in extracted) {
        final description = raw
            ? row.transaction.description
            : maskStructure(row.transaction.description);
        final trimmed = description.length > 44
            ? description.substring(0, 44)
            : description;
        stdout.writeln(
          '  ${formatIsoDate(row.transaction.date)}  '
          '${row.transaction.amount.toDecimalString().padLeft(11)}  '
          'bal ${(row.balance?.toDecimalString() ?? "—").padLeft(11)}  '
          '$trimmed',
        );
      }
    }

    for (final mismatch in check.mismatches.take(5)) {
      final description = raw
          ? mismatch.row.transaction.description
          : maskStructure(mismatch.row.transaction.description);
      stdout.writeln(
        '  !! row ${mismatch.index}: expected '
        '${mismatch.expected.toDecimalString()}, statement says '
        '${mismatch.actual.toDecimalString()} '
        '(off by ${mismatch.drift.toDecimalString()})  $description',
      );
    }
  }

  if (files.length > 1) {
    final consistency = totalChecked == 0
        ? 1.0
        : (totalChecked - totalMismatches) / totalChecked;
    stdout
      ..writeln()
      ..writeln('--- across ${files.length} statements ---')
      ..writeln('transactions : $totalTransactions')
      ..writeln('checked rows : $totalChecked')
      ..writeln('mismatches   : $totalMismatches')
      ..writeln(
        'consistency  : ${(consistency * 100).toStringAsFixed(2)}%',
      );
  }
}
