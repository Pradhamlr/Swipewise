import 'package:meta/meta.dart';
import 'package:statement_parser/src/model/money.dart';

/// An amount read off a statement, and whether the text said which way it went.
@immutable
class ParsedAmount {
  const ParsedAmount({required this.value, required this.signExplicit});

  /// Signed when [signExplicit]; otherwise the bare magnitude, and the caller
  /// decides the sign from which column it came out of.
  final Money value;

  /// True when the text itself carried direction — a `Dr`/`Cr` marker, a
  /// trailing minus, or brackets.
  final bool signExplicit;

  @override
  String toString() => '${value.toDecimalString()}'
      '${signExplicit ? " (explicit)" : ""}';
}

/// Parse an amount as printed on an Indian statement.
///
/// [Money.parse] is deliberately strict and understands only a plain decimal.
/// Issuers are not plain. The same rupee value shows up as `1,234.50`,
/// `1,234.50 Dr`, `1,234.50-`, `(1,234.50)`, `Rs. 1,234.50` or `₹1,234.50 CR`,
/// and getting the *direction* wrong silently inverts a transaction — which is
/// far worse than failing to parse it. So every quirk is handled explicitly
/// here and anything unrecognised returns null rather than a guess.
///
/// Returns null when [text] is not an amount at all, which is the common case:
/// most cells on a statement page are not amounts.
ParsedAmount? parseStatementAmount(String text) {
  var value = text.trim();
  if (value.isEmpty) return null;

  var negative = false;
  var explicit = false;

  // Currency noise, in the forms that actually appear.
  value = value
      .replaceAll('₹', '') // ₹
      .replaceAll(RegExp(r'^(INR|Rs\.?)\s*', caseSensitive: false), '')
      .trim();

  // (1,234.50) — accountancy brackets for a negative.
  if (value.startsWith('(') && value.endsWith(')')) {
    negative = true;
    explicit = true;
    value = value.substring(1, value.length - 1).trim();
  }

  // Dr / Cr markers, leading or trailing, with or without a dot.
  final marker = RegExp(
    r'^(?:(DR|CR)\.?\s+)?(.*?)(?:\s*(DR|CR)\.?)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (marker != null) {
    final found = marker.group(1) ?? marker.group(3);
    if (found != null) {
      explicit = true;
      // Dr is money leaving the account; the project's convention is that a
      // debit is negative.
      negative = found.toUpperCase() == 'DR';
      value = marker.group(2)!.trim();
    }
  }

  // Trailing minus: 1,234.50-
  if (value.endsWith('-')) {
    negative = true;
    explicit = true;
    value = value.substring(0, value.length - 1).trim();
  }

  // Leading minus.
  if (value.startsWith('-')) {
    negative = true;
    explicit = true;
    value = value.substring(1).trim();
  }

  if (value.isEmpty) return null;

  // Must look like a number now: digits, optional grouping, optional decimals.
  if (!RegExp(r'^\d[\d,]*(\.\d{1,2})?$').hasMatch(value)) return null;

  final Money magnitude;
  try {
    magnitude = Money.parse(value);
  } on FormatException {
    return null;
  }

  return ParsedAmount(
    value: negative ? magnitude.negated : magnitude,
    signExplicit: explicit,
  );
}
