import 'package:statement_parser/statement_parser.dart';

/// The stages the import pipeline moves through, in order.
///
/// Named rather than a bare percentage because the progress bar is doing two
/// jobs: telling the user it is alive, and telling *me* which stage is slow
/// when the perf pass comes. A single 0–100 would answer neither.
enum ImportStage {
  reading('Reading the PDF'),
  extractingGlyphs('Extracting glyphs'),
  clusteringRows('Finding rows'),
  detectingColumns('Detecting columns'),
  extractingTransactions('Reading transactions'),
  resolvingMerchants('Identifying merchants'),
  done('Done');

  const ImportStage(this.label);
  final String label;
}

/// One transaction as it lands in the app: what the statement said, plus what
/// the merchant cascade made of it.
class ImportedTransaction {
  const ImportedTransaction({
    required this.date,
    required this.description,
    required this.amountPaise,
    required this.merchantName,
    required this.mcc,
    required this.tags,
    required this.resolutionStage,
    required this.confidence,
  });

  final DateTime date;

  /// Verbatim from the statement, never cleaned. The disambiguation screen
  /// shows this so the user can recognise what they are labelling.
  final String description;

  /// Negative for a spend.
  final int amountPaise;

  final String? merchantName;
  final int? mcc;
  final Set<String> tags;

  /// Which rung of the cascade answered, so the why panel can say how.
  final ResolutionStage resolutionStage;
  final double confidence;

  bool get isResolved => resolutionStage != ResolutionStage.unresolved;
  bool get isSpend => amountPaise < 0;
}

/// Everything an import produced, including the parts that went wrong.
class ImportResult {
  const ImportResult({
    required this.transactions,
    required this.glyphCount,
    required this.rowCount,
    required this.tableCount,
    required this.balanceChecked,
    required this.balanceMismatches,
    required this.elapsed,
  });

  final List<ImportedTransaction> transactions;

  final int glyphCount;
  final int rowCount;
  final int tableCount;

  /// Rows the running balance could verify, and how many disagreed. Surfaced
  /// in the UI rather than logged: an import that does not reconcile is one
  /// the user should not trust, and hiding that would be the dishonest choice.
  final int balanceChecked;
  final int balanceMismatches;

  final Duration elapsed;

  bool get reconciles => balanceMismatches == 0;

  double get consistency => balanceChecked == 0
      ? 1
      : (balanceChecked - balanceMismatches) / balanceChecked;

  int get unresolvedCount => transactions.where((t) => !t.isResolved).length;

  /// Distinct payees behind the unresolved transactions — the real size of
  /// the disambiguation queue, since one label clears every transaction with
  /// that payee.
  int get unknownPayeeCount {
    final payees = <String>{};
    for (final txn in transactions) {
      if (txn.isResolved) continue;
      payees.add(parseDescriptor(txn.description).best ?? txn.description);
    }
    return payees.length;
  }
}

/// Messages the import isolate sends back.
sealed class ImportEvent {
  const ImportEvent();
}

class ImportProgress extends ImportEvent {
  const ImportProgress(this.stage, {this.detail});
  final ImportStage stage;
  final String? detail;
}

class ImportSucceeded extends ImportEvent {
  const ImportSucceeded(this.result);
  final ImportResult result;
}

class ImportFailed extends ImportEvent {
  const ImportFailed(this.message, {this.needsPassword = false});
  final String message;

  /// Distinguished so the UI can re-prompt instead of showing a dead end.
  final bool needsPassword;
}
