const _months = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

final _numeric = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})$');
final _alpha = RegExp(
  r'^(\d{1,2})[-\s/]*([A-Za-z]{3,4})[-\s/]*(\d{2}|\d{4})$',
);

/// Parse a transaction date as printed on an Indian statement.
///
/// Day always comes first. Indian statements are unambiguously `DD-MM-YY`, and
/// treating `05-08-26` as May 8th would silently move a transaction into the
/// wrong cycle — which changes which cap it consumes and therefore the reward.
/// So the American ordering is not attempted at all, even as a fallback.
///
/// Handles `05-08-26`, `05/08/2026`, `5.8.26`, `05 Aug 2026`, `05-AUG-26`.
/// Returns null on anything else rather than guessing.
DateTime? parseStatementDate(String text) {
  final value = text.trim();
  if (value.isEmpty) return null;

  final numeric = _numeric.firstMatch(value);
  if (numeric != null) {
    return _build(
      day: int.parse(numeric.group(1)!),
      month: int.parse(numeric.group(2)!),
      yearText: numeric.group(3)!,
    );
  }

  final alpha = _alpha.firstMatch(value);
  if (alpha != null) {
    final month = _months[alpha.group(2)!.toLowerCase()];
    if (month == null) return null;
    return _build(
      day: int.parse(alpha.group(1)!),
      month: month,
      yearText: alpha.group(3)!,
    );
  }

  return null;
}

DateTime? _build({
  required int day,
  required int month,
  required String yearText,
}) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  var year = int.parse(yearText);
  if (yearText.length == 2) {
    // Statements are recent documents. A two-digit year of 70+ means the
    // 1900s, which for this app means "not a statement date" — but the pivot
    // is stated rather than assumed so it can be argued with.
    year += year >= 70 ? 1900 : 2000;
  }

  final date = DateTime.utc(year, month, day);
  // Rejects 31 February, which DateTime would silently roll into March.
  if (date.day != day || date.month != month) return null;
  return date;
}
