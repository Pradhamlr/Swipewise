import 'package:flutter_test/flutter_test.dart';
import 'package:statement_parser/statement_parser.dart';
import 'package:swipewise/import/import_events.dart';
import 'package:swipewise/import/import_pipeline.dart';

/// Glyphs laid out as a passbook row: date, description, ref, credit, debit,
/// balance. Written by hand so the pipeline can be tested with no PDF, no
/// device and no native library — which is the whole reason the glyph
/// boundary exists.
List<GlyphRun> passbookRow({
  required double baseline,
  required String date,
  required String description,
  required String debit,
  required String balance,
  String credit = '0',
}) {
  final glyphs = <GlyphRun>[];
  void put(double startX, String text) {
    for (var i = 0; i < text.length; i++) {
      if (text[i] == ' ') continue;
      glyphs.add(
        GlyphRun(
          text: text[i],
          pageIndex: 0,
          x: startX + i * 5,
          y: baseline - 8,
          width: 4,
          height: 8,
        ),
      );
    }
  }

  put(20, date);
  put(120, description);
  put(380, '-');
  put(430, credit);
  put(510, debit);
  put(600, balance);
  return glyphs;
}

List<GlyphRun> statement() => [
  ...passbookRow(
    baseline: 100,
    date: '05-08-26',
    description: 'UPI/DR/123456789012/Swiggy/YESB/swiggy/Food',
    debit: '300.00',
    balance: '700.00',
  ),
  ...passbookRow(
    baseline: 118,
    date: '06-08-26',
    description: 'UPI/DR/123456789013/Zomato/YESB/zomato/Food',
    debit: '200.00',
    balance: '500.00',
  ),
  ...passbookRow(
    baseline: 136,
    date: '07-08-26',
    description: 'UPI/DR/123456789014/QQZX/YESB/qqzx/Pay',
    debit: '100.00',
    balance: '400.00',
  ),
  ...passbookRow(
    baseline: 154,
    date: '08-08-26',
    description: 'UPI/DR/123456789015/Uber/YESB/uber/Ride',
    debit: '150.00',
    balance: '250.00',
  ),
];

void main() {
  group('runImportPipeline', () {
    test('turns glyphs into transactions end to end', () {
      final result = runImportPipeline(statement());

      expect(result.transactions, hasLength(4));
      expect(result.tableCount, 1);
      expect(result.glyphCount, greaterThan(0));
      expect(result.transactions.first.amountPaise, -30000);
      expect(result.transactions.first.date, DateTime.utc(2026, 8, 5));
    });

    test('reconciles against the running balance', () {
      final result = runImportPipeline(statement());
      expect(result.balanceChecked, 3);
      expect(result.balanceMismatches, 0);
      expect(result.reconciles, isTrue);
      expect(result.consistency, 1.0);
    });

    test('resolves the merchants it knows and flags the ones it does not', () {
      final result = runImportPipeline(statement());

      final swiggy = result.transactions.first;
      expect(swiggy.merchantName, 'Swiggy');
      expect(swiggy.mcc, 5814);
      expect(swiggy.isResolved, isTrue);

      final unknown = result.transactions.firstWhere(
        (t) => t.description.contains('QQZX'),
      );
      expect(unknown.isResolved, isFalse);
      expect(unknown.mcc, isNull, reason: 'never guess an MCC');
    });

    test('counts the disambiguation queue by payee, not by transaction', () {
      final result = runImportPipeline(statement());
      expect(result.unresolvedCount, 1);
      expect(result.unknownPayeeCount, 1);
    });

    test('reports every stage in order', () {
      final seen = <ImportStage>[];
      runImportPipeline(statement(), onStage: (stage, _) => seen.add(stage));

      expect(
        seen,
        containsAllInOrder([
          ImportStage.clusteringRows,
          ImportStage.detectingColumns,
          ImportStage.extractingTransactions,
          ImportStage.resolvingMerchants,
          ImportStage.done,
        ]),
      );
    });

    test('a learned alias resolves the queue on the next run', () {
      final resolver = MerchantResolver()..learn('QQZX', 'blinkit');
      final result = runImportPipeline(statement(), resolver: resolver);
      expect(result.unresolvedCount, 0);
    });

    test('empty input produces nothing rather than throwing', () {
      final result = runImportPipeline([]);
      expect(result.transactions, isEmpty);
      expect(result.reconciles, isTrue);
    });
  });
}
