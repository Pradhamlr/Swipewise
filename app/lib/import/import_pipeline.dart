import 'package:statement_parser/statement_parser.dart';
import 'package:swipewise/import/import_events.dart';

/// Everything downstream of the glyphs, as one pure function.
///
/// Deliberately separated from the isolate and from PDFium: this takes a list
/// of [GlyphRun] and returns an [ImportResult], so the whole parse can be
/// exercised in a plain unit test against a committed glyph dump — no device,
/// no file picker, no native library. Only the step that produces glyphs is
/// platform-bound, and it is the one step with nothing interesting in it.
ImportResult runImportPipeline(
  List<GlyphRun> glyphs, {
  void Function(ImportStage stage, String? detail)? onStage,
  MerchantResolver? resolver,
  TableSchema schema = TableSchema.bankPassbook,
}) {
  final started = DateTime.now();
  final merchants = resolver ?? MerchantResolver();

  onStage?.call(ImportStage.clusteringRows, null);
  final rows = const RowClusterer().cluster(glyphs);

  onStage?.call(ImportStage.detectingColumns, '${rows.length} rows');
  final regions = const TableLocator().locate(rows);

  onStage?.call(
    ImportStage.extractingTransactions,
    '${regions.length} ${regions.length == 1 ? "table" : "tables"}',
  );

  final extracted = <ExtractedRow>[];
  for (final region in regions) {
    final layout = const ColumnDetector().detect(region.anchorRows);
    extracted.addAll(TableExtractor(schema).extract(region.rows, layout));
  }

  final balance = reconcileRunningBalance(extracted);

  onStage?.call(
    ImportStage.resolvingMerchants,
    '${extracted.length} transactions',
  );

  final transactions = <ImportedTransaction>[];
  for (final row in extracted) {
    final match = merchants.resolve(row.transaction.description);
    transactions.add(
      ImportedTransaction(
        date: row.transaction.date,
        description: row.transaction.description,
        amountPaise: row.transaction.amount.paise,
        merchantName: match.displayName,
        mcc: match.mcc,
        tags: match.tags,
        resolutionStage: match.stage,
        confidence: match.confidence,
      ),
    );
  }

  onStage?.call(ImportStage.done, null);

  return ImportResult(
    transactions: transactions,
    glyphCount: glyphs.length,
    rowCount: rows.length,
    tableCount: regions.length,
    balanceChecked: balance.checkedRows,
    balanceMismatches: balance.mismatches.length,
    elapsed: DateTime.now().difference(started),
  );
}
