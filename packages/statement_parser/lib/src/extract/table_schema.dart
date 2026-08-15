/// What a detected column means.
///
/// Column *detection* is geometric and issuer-agnostic; column *meaning* is
/// the one thing that differs per issuer. Keeping the mapping in a tiny value
/// like this is what makes an issuer adapter forty lines instead of four
/// hundred — the adapter's whole job is producing one of these.
enum ColumnRole {
  /// Transaction date. Required; a row without a parseable one is treated as
  /// a continuation of the row above it.
  date,

  /// Cheque number, UPI reference, anything not worth keeping.
  reference,

  /// Merchant descriptor, verbatim.
  description,

  /// Money leaving the account. Becomes a negative amount.
  debit,

  /// Money arriving. Becomes a positive amount.
  credit,

  /// A single signed column, where direction comes from a `Dr`/`Cr` marker or
  /// a trailing minus instead of from which column the number sits in.
  amount,

  /// Running balance after the transaction. Not part of the transaction, but
  /// worth capturing — it is what makes extraction self-checking.
  balance,

  /// Present in the layout, meaningless to us.
  ignore,
}

/// Maps detected column positions to their meanings, left to right.
class TableSchema {
  const TableSchema(this.roles);

  /// Bank passbook shape: date, reference, credit, debit, running balance.
  static const bankPassbook = TableSchema([
    ColumnRole.date,
    ColumnRole.description,
    ColumnRole.reference,
    ColumnRole.credit,
    ColumnRole.debit,
    ColumnRole.balance,
  ]);

  final List<ColumnRole> roles;

  /// Index of the first column with this role, or null.
  int? columnFor(ColumnRole role) {
    final index = roles.indexOf(role);
    return index < 0 ? null : index;
  }

  bool get hasSplitColumns =>
      columnFor(ColumnRole.debit) != null ||
      columnFor(ColumnRole.credit) != null;

  int get columnCount => roles.length;
}
