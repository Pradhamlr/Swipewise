import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

StatementTransaction txn(String date, String description, String amount) {
  return StatementTransaction(
    date: parseIsoDate(date),
    description: description,
    amount: Money.parse(amount),
  );
}

void main() {
  final swiggy = txn('2026-05-03', 'SWIGGY BANGALORE', '-800.00');
  final amazon = txn('2026-05-04', 'AMAZON PAY INDIA PRIVAT', '-1500.00');
  final payment = txn('2026-05-07', 'PAYMENT RECEIVED', '12500.00');

  group('scoreExtraction', () {
    test('a perfect parse scores 100% and reports nothing outstanding', () {
      final score = scoreExtraction(
        truth: [swiggy, amazon, payment],
        predicted: [swiggy, amazon, payment],
      );

      expect(score.recall, 1);
      expect(score.precision, 1);
      expect(score.f1, 1);
      expect(score.isPerfect, isTrue);
      expect(score.missed, isEmpty);
      expect(score.spurious, isEmpty);
    });

    test('order does not matter', () {
      final score = scoreExtraction(
        truth: [swiggy, amazon, payment],
        predicted: [payment, swiggy, amazon],
      );
      expect(score.isPerfect, isTrue);
    });

    test('a dropped row is a miss, not a silent pass', () {
      final score = scoreExtraction(
        truth: [swiggy, amazon, payment],
        predicted: [swiggy, payment],
      );

      expect(score.recall, closeTo(2 / 3, 1e-9));
      expect(score.precision, 1);
      expect(score.missed, [amazon]);
      expect(score.spurious, isEmpty);
    });

    test('an invented row costs precision', () {
      // A balance line mistaken for a transaction is the classic case.
      final balance = txn('2026-05-31', 'CLOSING BALANCE', '-9300.00');
      final score = scoreExtraction(
        truth: [swiggy, amazon],
        predicted: [swiggy, amazon, balance],
      );

      expect(score.recall, 1);
      expect(score.precision, closeTo(2 / 3, 1e-9));
      expect(score.spurious, [balance]);
    });

    test('duplicate transactions are matched as a multiset', () {
      // Two identical UPI transfers on the same day is a real statement,
      // not a bug. Set matching would score a parser that finds one of them
      // as perfect.
      final upi = txn('2026-05-11', 'UPI/PAYTM', '-100.00');
      final score = scoreExtraction(
        truth: [upi, upi],
        predicted: [upi],
      );

      expect(score.matched, 1);
      expect(score.recall, 0.5);
      expect(score.missed, [upi]);
      expect(score.spurious, isEmpty);
    });

    test('an extra duplicate is spurious', () {
      final upi = txn('2026-05-11', 'UPI/PAYTM', '-100.00');
      final score = scoreExtraction(
        truth: [upi],
        predicted: [upi, upi],
      );

      expect(score.matched, 1);
      expect(score.recall, 1);
      expect(score.precision, 0.5);
      expect(score.spurious, [upi]);
    });

    test('empty against empty is a vacuous pass, not a divide by zero', () {
      final score = scoreExtraction(truth: [], predicted: []);
      expect(score.precision, 1);
      expect(score.recall, 1);
      expect(score.f1, 1);
    });

    test('finding nothing scores zero rather than throwing', () {
      final score = scoreExtraction(truth: [swiggy], predicted: []);
      expect(score.recall, 0);
      expect(score.precision, 0);
      expect(score.f1, 0);
    });
  });

  group('MatchMode', () {
    // The row was found, but the description column was read wrong.
    final misread = txn('2026-05-03', 'SWIGGY BANGALO', '-800.00');

    test('segmentation mode isolates clustering from column reading', () {
      final score = scoreExtraction(
        truth: [swiggy],
        predicted: [misread],
        mode: MatchMode.segmentation,
      );
      expect(score.recall, 1, reason: 'the row itself was found');
    });

    test('strict mode catches what segmentation mode forgives', () {
      final score = scoreExtraction(
        truth: [swiggy],
        predicted: [misread],
      );
      expect(score.recall, 0);
      expect(score.missed, [swiggy]);
      expect(score.spurious, [misread]);
    });

    test('descriptor comparison ignores case and whitespace runs', () {
      final spaced = txn('2026-05-03', '  swiggy   bangalore ', '-800.00');
      final score = scoreExtraction(truth: [swiggy], predicted: [spaced]);
      expect(score.recall, 1);
    });

    test('descriptor comparison does not strip aggregator prefixes', () {
      // Collapsing RAZORPAY*ZOMATO to ZOMATO is Layer 2's job. If scoring
      // did it, a parser that dropped the prefix would look correct here.
      final raw = txn('2026-05-09', 'RAZORPAY*ZOMATO', '-450.00');
      final cleaned = txn('2026-05-09', 'ZOMATO', '-450.00');
      final score = scoreExtraction(truth: [raw], predicted: [cleaned]);
      expect(score.recall, 0);
    });
  });

  group('LabeledStatement', () {
    const source = '''
{
  "statement_id": "sbi-2026-05",
  "issuer": "sbi",
  "glyph_fixture": "fixtures/glyphs/redacted/sbi-2026-05.json",
  "transactions": [
    { "date": "2026-05-03", "description": "SWIGGY BANGALORE",
      "amount": "-800.00" },
    { "date": "2026-05-07", "description": "PAYMENT RECEIVED",
      "amount": "12500.00" }
  ]
}
''';

    test('parses the on-disk label format', () {
      final labeled = LabeledStatement.parse(source);

      expect(labeled.statementId, 'sbi-2026-05');
      expect(labeled.issuer, 'sbi');
      expect(labeled.transactions, hasLength(2));
      expect(labeled.transactions.first, equals(swiggy));
      expect(labeled.transactions.last.amount.isCredit, isTrue);
    });

    test('survives a round trip', () {
      final labeled = LabeledStatement.parse(source);
      final again = LabeledStatement.parse(labeled.toPrettyJson());
      expect(again.transactions, equals(labeled.transactions));
      expect(again.glyphFixture, labeled.glyphFixture);
    });

    test('scores itself perfectly, which keeps the harness honest', () {
      final labeled = LabeledStatement.parse(source);
      final score = scoreExtraction(
        truth: labeled.transactions,
        predicted: labeled.transactions,
      );
      expect(score.isPerfect, isTrue);
    });
  });
}
