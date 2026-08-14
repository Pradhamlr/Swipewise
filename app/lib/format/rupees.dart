/// Format paise as rupees with Indian digit grouping.
///
/// Indian grouping is not every three digits: it is the last three, then twos.
/// 1234567 paise is ₹12,345.67 and 123456789 is ₹12,34,567.89. Using a Western
/// grouping in an Indian fintech app is the kind of detail a reviewer notices
/// immediately, so it is worth the twenty lines rather than pulling in `intl`.
String formatRupees(int paise, {bool withSymbol = true, bool decimals = true}) {
  final negative = paise < 0;
  final magnitude = paise.abs();
  final rupees = magnitude ~/ 100;
  final fraction = (magnitude % 100).toString().padLeft(2, '0');

  final digits = rupees.toString();
  final String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }

  final sign = negative ? '-' : '';
  final symbol = withSymbol ? '₹' : '';
  final tail = decimals ? '.$fraction' : '';
  return '$sign$symbol$grouped$tail';
}
