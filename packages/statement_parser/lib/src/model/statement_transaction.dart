import 'package:meta/meta.dart';
import 'package:statement_parser/src/model/money.dart';

/// One transaction row as a human reads it off a statement.
///
/// This is the parser's output type *and* the ground-truth type. Scoring
/// compares two lists of these — one hand-labelled, one produced by the
/// pipeline — so there is deliberately no separate "expected" model to drift
/// out of sync.
///
/// A row is one *transaction*, not one printed line. A description that wraps
/// across three lines is still a single [StatementTransaction] with its
/// description joined by single spaces. Header rows, page furniture, opening
/// and closing balances and reward-point summaries are not transactions and
/// must not appear.
@immutable
class StatementTransaction {
  const StatementTransaction({
    required this.date,
    required this.description,
    required this.amount,
  });

  factory StatementTransaction.fromJson(Map<String, dynamic> json) {
    return StatementTransaction(
      date: parseIsoDate(json['date'] as String),
      description: json['description'] as String,
      amount: Money.parse(json['amount'] as String),
    );
  }

  /// Transaction date, not posting date, where the statement distinguishes
  /// them. Always UTC midnight — this is a calendar date, not an instant.
  final DateTime date;

  /// The descriptor exactly as printed, with wrapped lines joined by single
  /// spaces and leading/trailing whitespace removed. Not normalized, not
  /// title-cased, not cleaned of aggregator prefixes — that happens later,
  /// and scoring this stage against a cleaned string would hide parser bugs.
  final String description;

  /// Negative for a debit (a spend), positive for a credit.
  final Money amount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'date': formatIsoDate(date),
        'description': description,
        'amount': amount.toDecimalString(),
      };

  /// Identity used when scoring *segmentation* only: did the pipeline find a
  /// row on this date for this amount, regardless of whether it read the
  /// descriptor correctly?
  ///
  /// Separating this from [strictKey] is what makes a failure diagnosable —
  /// a row missing from both means clustering failed, while a row present
  /// here but absent from [strictKey] means the columns were misread.
  String get segmentationKey => '${formatIsoDate(date)}|${amount.paise}';

  /// Identity used when scoring the full extraction, descriptor included.
  String get strictKey =>
      '$segmentationKey|${normalizeDescription(description)}';

  @override
  String toString() =>
      '${formatIsoDate(date)}  ${amount.toDecimalString().padLeft(12)}  '
      '$description';

  @override
  bool operator ==(Object other) =>
      other is StatementTransaction &&
      other.date == date &&
      other.description == description &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(date, description, amount);
}

/// Compare descriptors case-insensitively with runs of whitespace collapsed.
///
/// Deliberately conservative: it does not strip punctuation or aggregator
/// prefixes. `RAZORPAY*ZOMATO` and `ZOMATO` are different strings here, and
/// should be — collapsing them is Layer 2's job, and doing it during scoring
/// would let a parser that drops the prefix look correct.
String normalizeDescription(String description) =>
    description.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// `YYYY-MM-DD` for a UTC calendar date.
String formatIsoDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Parse `YYYY-MM-DD` into a UTC midnight [DateTime].
DateTime parseIsoDate(String value) {
  final parsed = DateTime.parse(value);
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}
