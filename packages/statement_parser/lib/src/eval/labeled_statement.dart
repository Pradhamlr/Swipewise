import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:statement_parser/src/model/statement_transaction.dart';

/// A hand-labelled statement: the glyph fixture to parse, and every
/// transaction a human read off the original PDF.
///
/// One of these per statement lives in `fixtures/labels/`. Labelling is slow
/// and boring and is the only thing that makes the accuracy claim mean
/// anything, so the format is kept small enough to write by hand:
///
/// ```json
/// {
///   "statement_id": "sbi-2026-05",
///   "issuer": "sbi",
///   "glyph_fixture": "fixtures/glyphs/redacted/sbi-2026-05.json",
///   "transactions": [
///     { "date": "2026-05-03", "description": "SWIGGY BANGALORE",
///       "amount": "-800.00" },
///     { "date": "2026-05-07", "description": "PAYMENT RECEIVED",
///       "amount": "12500.00" }
///   ]
/// }
/// ```
///
/// Rules for whoever is labelling, including future you:
///
/// * **One entry per transaction, not per printed line.** A descriptor wrapped
///   over three lines is one entry, joined by single spaces.
/// * **Copy the descriptor verbatim.** Do not tidy it, expand abbreviations or
///   strip aggregator prefixes. The parser is scored on reading what is
///   printed; cleaning it up here would mark a broken parser correct.
/// * **Negative is a debit.** Refunds, payments and cashback are positive.
/// * **Exclude everything that is not a transaction**: opening and closing
///   balances, subtotals, reward-point summaries, page headers, EMI schedules
///   that have not been charged this cycle.
/// * **Include transactions you think the parser will miss.** The label file
///   describes the statement, never the parser's current abilities.
@immutable
class LabeledStatement {
  const LabeledStatement({
    required this.statementId,
    required this.issuer,
    required this.glyphFixture,
    required this.transactions,
  });

  factory LabeledStatement.fromJson(Map<String, dynamic> json) {
    final rows = json['transactions'] as List<dynamic>;
    return LabeledStatement(
      statementId: json['statement_id'] as String,
      issuer: json['issuer'] as String,
      glyphFixture: json['glyph_fixture'] as String,
      transactions: rows
          .map(
            (row) => StatementTransaction.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  factory LabeledStatement.parse(String source) =>
      LabeledStatement.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Stable identifier, also the fixture filename stem.
  final String statementId;

  /// Issuer slug, e.g. `sbi`. Per-issuer accuracy is reported by grouping on
  /// this, which is the table the README has to carry.
  final String issuer;

  /// Repo-relative path to the glyph JSON this statement was dumped to.
  final String glyphFixture;

  final List<StatementTransaction> transactions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'statement_id': statementId,
        'issuer': issuer,
        'glyph_fixture': glyphFixture,
        'transactions':
            transactions.map((t) => t.toJson()).toList(growable: false),
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
