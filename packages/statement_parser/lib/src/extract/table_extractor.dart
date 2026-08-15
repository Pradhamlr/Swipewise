import 'package:statement_parser/src/extract/table_schema.dart';
import 'package:statement_parser/src/geometry/column_detector.dart';
import 'package:statement_parser/src/geometry/glyph_row.dart';
import 'package:statement_parser/src/model/money.dart';
import 'package:statement_parser/src/model/statement_transaction.dart';
import 'package:statement_parser/src/normalize/amount_parser.dart';
import 'package:statement_parser/src/normalize/date_parser.dart';

/// A transaction plus what the statement printed alongside it.
class ExtractedRow {
  const ExtractedRow({
    required this.transaction,
    required this.pageIndex,
    this.balance,
  });

  final StatementTransaction transaction;

  /// Running balance after this transaction, when the statement prints one.
  final Money? balance;

  final int pageIndex;

  @override
  String toString() => '$transaction'
      '${balance == null ? "" : "  bal ${balance!.toDecimalString()}"}';
}

/// Turns clustered rows and a detected column layout into transactions.
class TableExtractor {
  const TableExtractor(this.schema, {this.unsignedAmountsAreDebits = true});

  final TableSchema schema;

  /// For single-column layouts with no `Dr`/`Cr` marker: does a bare number
  /// mean a spend? True for card statements, where nearly every line is one.
  final bool unsignedAmountsAreDebits;

  List<ExtractedRow> extract(List<GlyphRow> rows, ColumnLayout layout) {
    final out = <_Pending>[];

    for (final row in rows) {
      final cells = layout.cells(row);
      String? cell(ColumnRole role) {
        final index = schema.columnFor(role);
        if (index == null || index >= cells.length) return null;
        return cells[index]?.text.trim();
      }

      final date = parseStatementDate(cell(ColumnRole.date) ?? '');
      final description = cell(ColumnRole.description) ?? '';
      final amount = _amountFor(cell);

      if (date == null || amount == null) {
        // A row with no date and no amount but some text is a wrapped
        // descriptor — statements break long merchant names across lines, and
        // the continuation belongs to the transaction above it, not to a
        // transaction of its own.
        if (out.isNotEmpty && description.isNotEmpty && amount == null) {
          out.last.description = '${out.last.description} $description'.trim();
        }
        continue;
      }

      out.add(
        _Pending(
          date: date,
          description: description,
          amount: amount,
          balance: _balanceFor(cell),
          pageIndex: row.pageIndex,
        ),
      );
    }

    return [
      for (final pending in out)
        ExtractedRow(
          transaction: StatementTransaction(
            date: pending.date,
            description: pending.description,
            amount: pending.amount,
          ),
          balance: pending.balance,
          pageIndex: pending.pageIndex,
        ),
    ];
  }

  Money? _amountFor(String? Function(ColumnRole) cell) {
    if (schema.hasSplitColumns) {
      final debit = parseStatementAmount(cell(ColumnRole.debit) ?? '');
      final credit = parseStatementAmount(cell(ColumnRole.credit) ?? '');

      // Passbooks print 0.00 in the column that does not apply, so "which
      // column is non-zero" is the signal, not "which column is present".
      final debitValue = debit?.value.absolute ?? Money.zero;
      final creditValue = credit?.value.absolute ?? Money.zero;

      if (!debitValue.isZero) return debitValue.negated;
      if (!creditValue.isZero) return creditValue;
      return null;
    }

    final parsed = parseStatementAmount(cell(ColumnRole.amount) ?? '');
    if (parsed == null) return null;
    if (parsed.signExplicit) return parsed.value;
    return unsignedAmountsAreDebits ? parsed.value.negated : parsed.value;
  }

  Money? _balanceFor(String? Function(ColumnRole) cell) {
    final text = cell(ColumnRole.balance);
    if (text == null) return null;
    return parseStatementAmount(text)?.value;
  }
}

class _Pending {
  _Pending({
    required this.date,
    required this.description,
    required this.amount,
    required this.pageIndex,
    this.balance,
  });

  final DateTime date;
  String description;
  final Money amount;
  final Money? balance;
  final int pageIndex;
}
