import 'dart:math' as math;

/// Jaro similarity: 0 for nothing in common, 1 for identical.
///
/// Written out rather than pulled from a package because it is forty lines and
/// because the *tuning* matters more than the algorithm — the thresholds below
/// were chosen against real statement descriptors, and a black-box dependency
/// would make that impossible to reason about.
double jaro(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;

  // Characters only count as matching if they are near each other.
  final window = math.max(0, (math.max(a.length, b.length) ~/ 2) - 1);

  final aMatched = List<bool>.filled(a.length, false);
  final bMatched = List<bool>.filled(b.length, false);

  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final from = math.max(0, i - window);
    final to = math.min(b.length - 1, i + window);
    for (var j = from; j <= to; j++) {
      if (bMatched[j] || a[i] != b[j]) continue;
      aMatched[i] = true;
      bMatched[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0;

  // Matched characters that appear in a different order.
  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!aMatched[i]) continue;
    while (!bMatched[k]) {
      k++;
    }
    if (a[i] != b[k]) transpositions++;
    k++;
  }

  final m = matches.toDouble();
  return (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3;
}

/// Jaro-Winkler: Jaro, biased toward strings that agree at the start.
///
/// The prefix bonus is the right bias for merchant names. Statements truncate
/// from the right — `AMAZON PAY INDIA PRIVAT` — so a shared prefix is strong
/// evidence while a shared suffix is often just `INDIA` or `PVT LTD`.
double jaroWinkler(
  String a,
  String b, {
  double prefixScale = 0.1,
  int maxPrefix = 4,
}) {
  final base = jaro(a, b);
  if (base == 0) return 0;

  var prefix = 0;
  final limit = math.min(maxPrefix, math.min(a.length, b.length));
  while (prefix < limit && a[prefix] == b[prefix]) {
    prefix++;
  }

  return base + prefix * prefixScale * (1 - base);
}

/// Character trigrams, padded so the start and end of the string carry weight.
Set<String> trigrams(String value) {
  final padded = '  ${value.trim()} ';
  if (padded.length < 3) return const {};
  return {
    for (var i = 0; i <= padded.length - 3; i++) padded.substring(i, i + 3),
  };
}

/// Jaccard overlap of two strings' trigram sets.
///
/// Complements Jaro-Winkler rather than duplicating it: Jaro-Winkler cares
/// about character order and position, trigrams care about shared substrings
/// wherever they appear. `BIGBASKET` vs `BASKET BIG` scores poorly on the
/// first and well on the second, and real descriptors reorder words often
/// enough that both signals are worth having.
double trigramSimilarity(String a, String b) {
  final left = trigrams(a);
  final right = trigrams(b);
  if (left.isEmpty || right.isEmpty) return 0;

  var shared = 0;
  for (final gram in left) {
    if (right.contains(gram)) shared++;
  }
  final union = left.length + right.length - shared;
  return union == 0 ? 0 : shared / union;
}

/// Combined similarity, taking the stronger of the two signals.
///
/// Deliberately a max rather than an average: the two measures fail in
/// different ways, so a confident answer from either is worth more than a
/// lukewarm consensus. The threshold that turns this into a decision lives in
/// the resolver, not here.
///
/// **Uses plain Jaro, not Jaro-Winkler.** The prefix bonus is the textbook
/// choice for name matching and it is wrong for this data. Indian entity names
/// share leading words at an unusual rate — `INDIAN`, `SHREE`, `SRI`, `NEW`,
/// `BHARAT` — so the bonus rewards exactly the coincidence that should be
/// treated with suspicion. Measured on real statements: `INDIANC` matched
/// `INDIANOIL` 56 times, scoring 0.841 on Jaro and 0.905 once Winkler added
/// four characters of shared prefix. Every one of those was wrong, and each
/// would have marked a transaction as fuel — a category excluded from rewards
/// on every card, so the error would have silently zeroed real spending.
///
/// [jaroWinkler] is kept and tested because it is the right tool where a
/// shared prefix genuinely is evidence; it just is not the gate here.
double merchantSimilarity(String a, String b) {
  final left = a.toUpperCase().trim();
  final right = b.toUpperCase().trim();
  if (left == right) return 1;
  return math.max(jaro(left, right), trigramSimilarity(left, right));
}
