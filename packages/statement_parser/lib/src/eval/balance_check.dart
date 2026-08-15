import 'package:meta/meta.dart';
import 'package:statement_parser/src/extract/table_extractor.dart';
import 'package:statement_parser/src/model/money.dart';

/// One row where the running balance did not follow from the row before it.
@immutable
class BalanceMismatch {
  const BalanceMismatch({
    required this.index,
    required this.expected,
    required this.actual,
    required this.row,
  });

  /// Position in the extracted list.
  final int index;

  /// What the previous balance plus this row's amount comes to.
  final Money expected;

  /// What the statement actually printed.
  final Money actual;

  final ExtractedRow row;

  Money get drift => Money(actual.paise - expected.paise);

  @override
  String toString() => 'row $index: expected ${expected.toDecimalString()}, '
      'statement says ${actual.toDecimalString()} '
      '(off by ${drift.toDecimalString()}) — ${row.transaction}';
}

/// The result of checking a statement against its own arithmetic.
@immutable
class BalanceReconciliation {
  const BalanceReconciliation({
    required this.checkedRows,
    required this.mismatches,
  });

  /// How many rows could be checked — those with a balance on both this row
  /// and the one before it.
  final int checkedRows;

  final List<BalanceMismatch> mismatches;

  bool get isConsistent => mismatches.isEmpty;

  /// Fraction of checkable rows that reconciled. 1.0 when nothing could be
  /// checked, because "no evidence of error" is the honest reading.
  double get consistency {
    if (checkedRows == 0) return 1;
    return (checkedRows - mismatches.length) / checkedRows;
  }

  @override
  String toString() => 'balance: ${mismatches.length} mismatches of '
      '$checkedRows checked rows';
}

/// Verify extracted rows against the statement's own running balance.
///
/// `balance[i] == balance[i-1] + amount[i]`, with debits negative. A statement
/// that prints a running balance is therefore **self-checking**: a dropped
/// row, a duplicated row, a misread amount or a debit parsed as a credit all
/// break the chain immediately, and the break points at the row that caused it.
///
/// This matters more than it looks. Hand-labelling ground truth is the slowest
/// part of measuring a parser, and this needs none — every statement carrying
/// a balance column validates its own extraction for free. It cannot catch an
/// error in the *description*, only in dates, amounts and row boundaries, so
/// it complements hand-labelled accuracy rather than replacing it.
BalanceReconciliation reconcileRunningBalance(List<ExtractedRow> rows) {
  final mismatches = <BalanceMismatch>[];
  var checked = 0;

  for (var i = 1; i < rows.length; i++) {
    final previous = rows[i - 1].balance;
    final current = rows[i].balance;
    if (previous == null || current == null) continue;

    checked++;
    final expected = previous + rows[i].transaction.amount;
    if (expected != current) {
      mismatches.add(
        BalanceMismatch(
          index: i,
          expected: expected,
          actual: current,
          row: rows[i],
        ),
      );
    }
  }

  return BalanceReconciliation(checkedRows: checked, mismatches: mismatches);
}
