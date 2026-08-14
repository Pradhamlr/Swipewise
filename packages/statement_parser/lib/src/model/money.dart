import 'package:meta/meta.dart';

/// An amount in Indian paise.
///
/// Money is never a `double` here. Reward maths multiplies amounts by rates
/// like 0.05 and compares the results against caps, and binary floating point
/// makes those comparisons unreliable in exactly the cases that matter — a
/// transaction sitting on a cap boundary.
///
/// Sign convention throughout the project: **negative is a debit** (money
/// leaving the account, i.e. a spend), positive is a credit (refund, cashback,
/// payment received). Reward rules only ever apply to debits.
@immutable
class Money implements Comparable<Money> {
  const Money(this.paise);

  /// Parse a decimal amount as printed on a statement.
  ///
  /// Accepts an optional leading `-`, Indian digit grouping, and an optional
  /// two-digit fraction: `800`, `800.00`, `1,23,456.78`, `-1234.5`.
  ///
  /// Deliberately strict — it does **not** understand `Dr`/`Cr` suffixes,
  /// trailing minus, or parenthesised negatives. Those are issuer presentation
  /// quirks and belong in the normalization stage, which decides what the sign
  /// should be before calling this.
  factory Money.parse(String input) {
    final trimmed = input.trim();
    final match = _pattern.firstMatch(trimmed);
    if (match == null) {
      throw FormatException('not a decimal amount', input);
    }

    final negative = match.group(1) == '-';
    final whole = match.group(2)!.replaceAll(',', '');
    final fraction = match.group(3) ?? '';
    final paddedFraction = fraction.padRight(2, '0');

    if (paddedFraction.length > 2) {
      throw FormatException('more than two decimal places', input);
    }

    final value = int.parse(whole) * 100 + int.parse(paddedFraction);
    return Money(negative ? -value : value);
  }

  static final RegExp _pattern = RegExp(r'^(-)?([\d,]+)(?:\.(\d+))?$');

  static const Money zero = Money(0);

  /// The amount in paise. 100 paise = ₹1.
  final int paise;

  bool get isDebit => paise < 0;
  bool get isCredit => paise > 0;
  bool get isZero => paise == 0;

  Money get absolute => paise < 0 ? Money(-paise) : this;
  Money get negated => Money(-paise);

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  /// Render as a plain decimal string, e.g. `-1234.50`. No grouping, no
  /// currency symbol — this is the on-disk form used by fixtures.
  String toDecimalString() {
    final sign = paise < 0 ? '-' : '';
    final magnitude = paise.abs();
    final rupees = magnitude ~/ 100;
    final fraction = (magnitude % 100).toString().padLeft(2, '0');
    return '$sign$rupees.$fraction';
  }

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  String toString() => toDecimalString();

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;
}
