import 'package:meta/meta.dart';
import 'package:statement_parser/src/model/statement_transaction.dart';

/// Which identity two transactions are matched on when scoring.
enum MatchMode {
  /// Date and amount only. Answers "was the row found at all?", isolating
  /// row clustering from column reading.
  segmentation,

  /// Date, amount and descriptor. The number the v0 gate is stated against.
  strict,
}

/// The result of scoring a parse against hand-laboured ground truth.
///
/// Matching is **multiset**, not set: a statement legitimately contains two
/// ₹100 UPI transfers on the same day with the same descriptor, and a parser
/// that emits one of them has made an error that set matching would hide.
@immutable
class ExtractionScore {
  const ExtractionScore({
    required this.mode,
    required this.truthCount,
    required this.predictedCount,
    required this.matched,
    required this.missed,
    required this.spurious,
  });

  final MatchMode mode;

  /// Number of transactions in the ground truth.
  final int truthCount;

  /// Number of transactions the parser produced.
  final int predictedCount;

  /// How many predictions were paired with a distinct ground-truth row.
  final int matched;

  /// Ground-truth rows the parser never produced.
  final List<StatementTransaction> missed;

  /// Rows the parser invented — usually header lines, balance rows or a
  /// description that got split into two transactions.
  final List<StatementTransaction> spurious;

  /// Of what the parser produced, how much was real.
  ///
  /// Defined as 1.0 when the parser produced nothing and there was nothing to
  /// find; that is a vacuous success rather than a failure.
  double get precision {
    if (predictedCount == 0) return truthCount == 0 ? 1 : 0;
    return matched / predictedCount;
  }

  /// Of what was there, how much the parser found. **This is the v0 gate.**
  double get recall {
    if (truthCount == 0) return 1;
    return matched / truthCount;
  }

  double get f1 {
    final p = precision;
    final r = recall;
    if (p + r == 0) return 0;
    return 2 * p * r / (p + r);
  }

  /// True when every row was found and nothing was invented.
  bool get isPerfect => missed.isEmpty && spurious.isEmpty;

  String get summary => '${mode.name}: recall ${_pct(recall)} '
      'precision ${_pct(precision)} '
      'f1 ${_pct(f1)}  '
      '($matched/$truthCount matched, ${spurious.length} spurious)';

  static String _pct(double value) => '${(value * 100).toStringAsFixed(1)}%';

  @override
  String toString() => summary;
}

/// Score a parse against ground truth.
///
/// Neither list needs to be sorted; ordering is not part of correctness here
/// because a statement's rows are already uniquely identified by date, amount
/// and descriptor, and imposing an order would fail parsers that are right but
/// emit pages in a different sequence.
ExtractionScore scoreExtraction({
  required List<StatementTransaction> truth,
  required List<StatementTransaction> predicted,
  MatchMode mode = MatchMode.strict,
}) {
  String keyOf(StatementTransaction transaction) => switch (mode) {
        MatchMode.segmentation => transaction.segmentationKey,
        MatchMode.strict => transaction.strictKey,
      };

  // Bucket the ground truth by key so duplicates are consumed one at a time.
  final unmatched = <String, List<StatementTransaction>>{};
  for (final transaction in truth) {
    unmatched.putIfAbsent(keyOf(transaction), () => []).add(transaction);
  }

  final spurious = <StatementTransaction>[];
  var matched = 0;

  for (final transaction in predicted) {
    final bucket = unmatched[keyOf(transaction)];
    if (bucket != null && bucket.isNotEmpty) {
      bucket.removeLast();
      matched++;
    } else {
      spurious.add(transaction);
    }
  }

  final missed = unmatched.values.expand((bucket) => bucket).toList();

  return ExtractionScore(
    mode: mode,
    truthCount: truth.length,
    predictedCount: predicted.length,
    matched: matched,
    missed: missed,
    spurious: spurious,
  );
}
