import 'package:meta/meta.dart';

/// What kind of rail a descriptor came off.
enum DescriptorKind {
  /// `UPI/DR/655483690475/JioHotstar/YESB/hotstaronl/Sub`
  upi,

  /// A card acquirer's descriptor: `RAZORPAY*ZOMATO`, `AMAZON PAY INDIA PRIV`.
  card,

  /// Recognised bank operations: interest, fees, ATM, cheque.
  bankOperation,

  /// Nothing matched a known shape.
  unknown,
}

/// A raw descriptor pulled apart into the bits worth matching on.
@immutable
class ParsedDescriptor {
  const ParsedDescriptor({
    required this.raw,
    required this.kind,
    required this.candidates,
    this.reference,
    this.handle,
    this.note,
  });

  final String raw;
  final DescriptorKind kind;

  /// Merchant-name guesses, best first. More than one because a UPI narration
  /// carries both a payee name and a VPA handle, and either may be the
  /// recognisable one — `JioHotstar` beats `hotstaronl`, but `q438734900`
  /// loses to whatever the payee field says.
  final List<String> candidates;

  /// The transaction reference, kept out of matching entirely. A twelve-digit
  /// number is pure noise to a fuzzy matcher and actively harmful — it drags
  /// trigram overlap toward whichever catalogue entry happens to share digits.
  final String? reference;

  /// The VPA handle, e.g. `hotstaronl` from `hotstaronl@ybl`.
  final String? handle;

  final String? note;

  String? get best => candidates.isEmpty ? null : candidates.first;

  @override
  String toString() => '$kind ${candidates.join(" | ")}';
}

const _aggregatorPrefixes = <String>[
  'RAZORPAY',
  'RAZP',
  'PAYU',
  'BILLDESK',
  'CCAVENUE',
  'PHONEPE',
  'PAYTM',
  'PINELABS',
  'CASHFREE',
  'INSTAMOJO',
];

/// Words that are never the merchant, only where or what it is.
const _noiseTokens = <String>{
  'INDIA',
  'IN',
  'PVT',
  'PRIVATE',
  'PRIVAT',
  'LTD',
  'LIMITED',
  'LLP',
  'COM',
  'ONLINE',
  'PAYMENT',
  'PAYMENTS',
  'UPI',
  'NA',
};

final _bankOperations = <RegExp, String>{
  RegExp(r'\b(ATM|CASH\s*WDL|CASH\s*WITHDRAWAL)\b'): 'atm',
  RegExp(r'\b(INT\.?PD|INTEREST|CREDIT INTEREST)\b'): 'interest',
  RegExp(r'\b(CHRG|CHARGES?|FEE|GST|SMS CHARGES)\b'): 'bank_charge',
  RegExp(r'\b(SALARY|SAL CREDIT|NEFT CR)\b'): 'salary',
  RegExp(r'\b(CHEQUE|CHQ|CLG)\b'): 'cheque',
};

/// Pull a raw statement descriptor apart into matchable candidates.
///
/// This is stage one of the cascade and the only stage that knows about the
/// *shape* of a descriptor. Everything after it works on plain name strings,
/// which is what keeps the fuzzy matcher honest — it never sees a reference
/// number or a bank code to accidentally match on.
ParsedDescriptor parseDescriptor(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return ParsedDescriptor(
      raw: raw,
      kind: DescriptorKind.unknown,
      candidates: const [],
    );
  }

  final upper = trimmed.toUpperCase();

  for (final entry in _bankOperations.entries) {
    if (entry.key.hasMatch(upper)) {
      return ParsedDescriptor(
        raw: raw,
        kind: DescriptorKind.bankOperation,
        candidates: [entry.value],
      );
    }
  }

  if (upper.startsWith('UPI/') || upper.startsWith('UPI-')) {
    return _parseUpi(trimmed);
  }

  return _parseCard(trimmed);
}

/// `UPI/DR/<ref>/<payee>/<bank>/<handle>/<note>` — field count varies by bank,
/// so positions are treated as hints and every plausible field is offered as a
/// candidate rather than trusting one slot.
ParsedDescriptor _parseUpi(String raw) {
  final parts = raw.split(RegExp('[/-]')).map((p) => p.trim()).toList();

  String? reference;
  String? handle;
  final candidates = <String>[];

  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) continue;

    final upper = part.toUpperCase();
    if (upper == 'DR' || upper == 'CR' || upper == 'UPI') continue;

    // A long digit run is the reference.
    if (RegExp(r'^\d{6,}$').hasMatch(part)) {
      reference ??= part;
      continue;
    }

    // Four-letter all-caps is an IFSC-style bank code.
    if (RegExp(r'^[A-Z]{4}$').hasMatch(part)) continue;

    // A handle is mostly lowercase and often carries digits.
    if (RegExp(r'^[a-z][a-z0-9._]*$').hasMatch(part)) {
      handle ??= part;
      if (!RegExp(r'^[a-z]?\d{5,}').hasMatch(part)) candidates.add(part);
      continue;
    }

    candidates.add(part);
  }

  final cleaned = <String>[];
  for (final candidate in candidates) {
    final value = _stripNoise(candidate);
    if (value.isNotEmpty && !cleaned.contains(value)) cleaned.add(value);
  }

  return ParsedDescriptor(
    raw: raw,
    kind: DescriptorKind.upi,
    candidates: cleaned,
    reference: reference,
    handle: handle,
    note: parts.length > 6 ? parts.last : null,
  );
}

ParsedDescriptor _parseCard(String raw) {
  var value = raw;

  // Aggregator prefixes: RAZORPAY*ZOMATO -> ZOMATO
  final star = value.indexOf('*');
  if (star > 0) {
    final prefix = value.substring(0, star).toUpperCase().trim();
    if (_aggregatorPrefixes.any(prefix.startsWith)) {
      value = value.substring(star + 1);
    }
  }

  final cleaned = _stripNoise(value);
  return ParsedDescriptor(
    raw: raw,
    kind: cleaned.isEmpty ? DescriptorKind.unknown : DescriptorKind.card,
    candidates: cleaned.isEmpty ? const [] : [cleaned],
  );
}

/// Drop reference numbers, corporate suffixes and location noise.
String _stripNoise(String value) {
  final tokens = value
      .toUpperCase()
      .replaceAll(RegExp('[^A-Z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .where((t) => !_noiseTokens.contains(t))
      .where((t) => !RegExp(r'^\d{4,}$').hasMatch(t))
      .toList();

  return tokens.join(' ').trim();
}
