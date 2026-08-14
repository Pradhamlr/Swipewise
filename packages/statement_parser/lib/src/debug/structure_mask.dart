/// Replace a string's *content* with its *shape*.
///
/// Uppercase letters become `A`, lowercase `a`, digits `9`. Punctuation,
/// symbols and spacing survive untouched, so
/// `SWIGGY BLR 04/05/26 1,234.50` becomes `AAAAAA AAA 99/99/99 9,999.99`.
///
/// This exists so a statement's *layout* can be inspected, pasted into an
/// issue or shown to someone else without disclosing a single real merchant,
/// name, card number or amount. Column positions, date formats and field
/// widths all survive; nothing identifying does.
///
/// It is a privacy convenience, not a security control — the shape of an
/// unusually long merchant name is still a weak signal — so masked output from
/// a real statement is low-sensitivity, not public.
String maskStructure(String input) {
  const upperA = 0x41; // A
  const upperZ = 0x5A; // Z
  const lowerA = 0x61; // a
  const lowerZ = 0x7A; // z
  const digit0 = 0x30; // 0
  const digit9 = 0x39; // 9

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= upperA && rune <= upperZ) {
      buffer.write('A');
    } else if (rune >= lowerA && rune <= lowerZ) {
      buffer.write('a');
    } else if (rune >= digit0 && rune <= digit9) {
      buffer.write('9');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
