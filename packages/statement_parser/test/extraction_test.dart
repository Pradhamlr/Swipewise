import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

GlyphRow rowAt({
  required double centerY,
  required Map<double, String> cells,
  int page = 0,
}) {
  final glyphs = <GlyphRun>[];
  cells.forEach((startX, text) {
    for (var i = 0; i < text.length; i++) {
      if (text[i] == ' ') continue;
      glyphs.add(
        GlyphRun(
          text: text[i],
          pageIndex: page,
          x: startX + i * 5,
          y: centerY - 4,
          width: 4,
          height: 8,
        ),
      );
    }
  });
  glyphs.sort((a, b) => a.x.compareTo(b.x));
  return GlyphRow(pageIndex: page, glyphs: glyphs);
}

/// Date | Description | Ref | Credit | Debit | Balance — the shape a bank
/// passbook and most card statements share.
GlyphRow passbookRow({
  required double centerY,
  required String date,
  required String description,
  required String balance,
  String reference = '-',
  String credit = '0',
  String debit = '0',
}) {
  return rowAt(
    centerY: centerY,
    cells: {
      20: date,
      120: description,
      380: reference,
      430: credit,
      510: debit,
      600: balance,
    },
  );
}

void main() {
  group('parseStatementAmount', () {
    test('reads plain and grouped amounts without a sign', () {
      final parsed = parseStatementAmount('1,234.50')!;
      expect(parsed.value, Money.parse('1234.50'));
      expect(parsed.signExplicit, isFalse);
    });

    test('Dr means money left the account', () {
      final parsed = parseStatementAmount('1,234.50 Dr')!;
      expect(parsed.value, Money.parse('-1234.50'));
      expect(parsed.signExplicit, isTrue);
    });

    test('Cr means money arrived', () {
      expect(parseStatementAmount('500.00 CR')!.value, Money.parse('500.00'));
      expect(parseStatementAmount('CR 500.00')!.value, Money.parse('500.00'));
    });

    test('trailing minus and brackets both mean negative', () {
      expect(parseStatementAmount('800.00-')!.value, Money.parse('-800.00'));
      expect(parseStatementAmount('(800.00)')!.value, Money.parse('-800.00'));
    });

    test('strips currency noise', () {
      expect(parseStatementAmount('₹1,234.50')!.value, Money.parse('1234.50'));
      expect(parseStatementAmount('Rs. 99.00')!.value, Money.parse('99.00'));
      expect(parseStatementAmount('INR 99')!.value, Money.parse('99'));
    });

    test('returns null on anything that is not an amount', () {
      for (final text in ['', '  ', 'SWIGGY', '05-08-26', 'Dr', '12.345']) {
        expect(
          parseStatementAmount(text),
          isNull,
          reason: 'should not parse "$text"',
        );
      }
    });
  });

  group('parseStatementDate', () {
    test('reads day-first numeric dates', () {
      expect(parseStatementDate('05-08-26'), DateTime.utc(2026, 8, 5));
      expect(parseStatementDate('05/08/2026'), DateTime.utc(2026, 8, 5));
      expect(parseStatementDate('5.8.26'), DateTime.utc(2026, 8, 5));
    });

    test('reads alphabetic months', () {
      expect(parseStatementDate('05 Aug 2026'), DateTime.utc(2026, 8, 5));
      expect(parseStatementDate('05-AUG-26'), DateTime.utc(2026, 8, 5));
    });

    test('is day-first, never month-first', () {
      // 05-08-26 is 5 August. Reading it as 8 May would move the transaction
      // into a different statement cycle and therefore a different cap.
      expect(parseStatementDate('05-08-26')!.month, 8);
      // 13 cannot be a month, so a month-first reader would fail here; a
      // day-first one must not.
      expect(parseStatementDate('13-08-26'), DateTime.utc(2026, 8, 13));
    });

    test('rejects impossible dates rather than rolling them over', () {
      expect(parseStatementDate('31-02-26'), isNull);
      expect(parseStatementDate('05-13-26'), isNull);
      expect(parseStatementDate('SWIGGY'), isNull);
      expect(parseStatementDate(''), isNull);
    });
  });

  group('TableExtractor', () {
    final rows = [
      passbookRow(
        centerY: 100,
        date: '05-08-26',
        description: 'SWIGGY BLR',
        debit: '30.00',
        balance: '230.53',
      ),
      passbookRow(
        centerY: 115,
        date: '06-08-26',
        description: 'AMAZON IN',
        debit: '13.00',
        balance: '217.53',
      ),
      passbookRow(
        centerY: 130,
        date: '07-08-26',
        description: 'SALARY',
        credit: '1500.00',
        balance: '1717.53',
      ),
    ];

    late ColumnLayout layout;
    setUp(() => layout = const ColumnDetector().detect(rows));

    const extractor = TableExtractor(TableSchema.bankPassbook);

    test('a debit becomes a negative amount', () {
      final extracted = extractor.extract(rows, layout);
      expect(extracted, hasLength(3));
      expect(extracted.first.transaction.amount, Money.parse('-30.00'));
      expect(extracted.first.transaction.description, 'SWIGGY BLR');
      expect(extracted.first.transaction.date, DateTime.utc(2026, 8, 5));
    });

    test('a credit becomes a positive amount', () {
      final extracted = extractor.extract(rows, layout);
      expect(extracted.last.transaction.amount, Money.parse('1500.00'));
      expect(extracted.last.transaction.amount.isCredit, isTrue);
    });

    test('captures the running balance alongside', () {
      final extracted = extractor.extract(rows, layout);
      expect(extracted.first.balance, Money.parse('230.53'));
    });

    test('a wrapped descriptor joins the transaction above it', () {
      // Statements break long merchant names across lines. The continuation
      // has no date and no amount and must not become its own transaction.
      final wrapped = [
        rows.first,
        rowAt(centerY: 108, cells: {120: 'CONTINUED HERE'}),
        rows[1],
      ];
      final wrappedLayout = const ColumnDetector().detect(wrapped);
      final extracted = extractor.extract(wrapped, wrappedLayout);

      expect(extracted, hasLength(2), reason: 'the continuation is not a txn');
      expect(
        extracted.first.transaction.description,
        'SWIGGY BLR CONTINUED HERE',
      );
    });

    test('rows with neither date nor amount are skipped', () {
      final withNoise = [
        rowAt(centerY: 80, cells: {20: 'DATE', 120: 'PARTICULARS'}),
        ...rows,
      ];
      final noisyLayout = const ColumnDetector().detect(withNoise);
      expect(extractor.extract(withNoise, noisyLayout), hasLength(3));
    });
  });

  group('reconcileRunningBalance', () {
    ExtractedRow row(String date, String amount, String balance) {
      return ExtractedRow(
        transaction: StatementTransaction(
          date: parseStatementDate(date)!,
          description: 'X',
          amount: Money.parse(amount),
        ),
        balance: Money.parse(balance),
        pageIndex: 0,
      );
    }

    test('a correctly extracted statement reconciles', () {
      final result = reconcileRunningBalance([
        row('05-08-26', '-30.00', '230.53'),
        row('06-08-26', '-13.00', '217.53'),
        row('07-08-26', '-20.00', '197.53'),
        row('08-08-26', '1500.00', '1697.53'),
      ]);

      expect(result.isConsistent, isTrue);
      expect(result.checkedRows, 3);
      expect(result.consistency, 1.0);
    });

    test('a dropped row breaks the chain and points at it', () {
      // Row two is missing, so the balance jumps by more than the amount.
      final result = reconcileRunningBalance([
        row('05-08-26', '-30.00', '230.53'),
        row('07-08-26', '-20.00', '197.53'),
      ]);

      expect(result.isConsistent, isFalse);
      expect(result.mismatches.single.index, 1);
      expect(result.mismatches.single.drift, Money.parse('-13.00'));
    });

    test('a debit misread as a credit is caught', () {
      final result = reconcileRunningBalance([
        row('05-08-26', '-30.00', '230.53'),
        row('06-08-26', '13.00', '217.53'),
      ]);
      expect(result.isConsistent, isFalse);
    });

    test('rows without balances are simply not checked', () {
      final result = reconcileRunningBalance([
        ExtractedRow(
          transaction: StatementTransaction(
            date: DateTime.utc(2026, 8, 5),
            description: 'X',
            amount: Money.parse('-30.00'),
          ),
          pageIndex: 0,
        ),
        ExtractedRow(
          transaction: StatementTransaction(
            date: DateTime.utc(2026, 8, 6),
            description: 'Y',
            amount: Money.parse('-13.00'),
          ),
          pageIndex: 0,
        ),
      ]);

      expect(result.checkedRows, 0);
      expect(result.consistency, 1.0, reason: 'no evidence of error');
    });
  });
}
