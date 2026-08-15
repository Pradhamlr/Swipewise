import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

GlyphRow textRow(String text, {required double centerY, int page = 0}) {
  final glyphs = <GlyphRun>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] == ' ') continue;
    glyphs.add(
      GlyphRun(
        text: text[i],
        pageIndex: page,
        x: i * 5,
        y: centerY - 4,
        width: 4,
        height: 8,
      ),
    );
  }
  return GlyphRow(pageIndex: page, glyphs: glyphs);
}

void main() {
  group('startsWithDate', () {
    test('accepts a leading date token', () {
      expect(startsWithDate('05-08-26 SWIGGY BLR 800.00'), isTrue);
      expect(startsWithDate('05/08/2026 AMAZON'), isTrue);
    });

    test('accepts a date welded to the text behind it', () {
      // Word-space reconstruction sometimes leaves a row unspaced.
      expect(startsWithDate('05-08-26SWIGGYBLR800.00'), isTrue);
    });

    test('rejects rows that merely contain a date', () {
      expect(startsWithDate('Statement period 05-08-26 to 04-09-26'), isFalse);
      expect(startsWithDate('PARTICULARS'), isFalse);
      expect(startsWithDate(''), isFalse);
    });
  });

  group('TableLocator', () {
    const locator = TableLocator();

    test('finds a run of dated rows and ignores page furniture', () {
      final rows = [
        textRow('SBI BANK STATEMENT', centerY: 40),
        textRow('Account Number 1234567890', centerY: 60),
        textRow('DATE PARTICULARS AMOUNT', centerY: 80),
        textRow('05-08-26 SWIGGY 30.00', centerY: 100),
        textRow('06-08-26 AMAZON 13.00', centerY: 115),
        textRow('07-08-26 UBER 20.00', centerY: 130),
        textRow('08-08-26 ZOMATO 55.00', centerY: 145),
        textRow('Please retain for your records', centerY: 300),
      ];

      final regions = locator.locate(rows);
      expect(regions, hasLength(1));
      expect(regions.single.anchorRows, hasLength(4));
      expect(regions.single.pageIndex, 0);
    });

    test('a lone dated line in a header is not a table', () {
      final rows = [
        textRow('Statement date 05-08-26', centerY: 40),
        textRow('Dear customer', centerY: 60),
        textRow('Thank you for banking with us', centerY: 80),
      ];
      expect(locator.locate(rows), isEmpty);
    });

    test('pulls in wrapped descriptors between dated rows', () {
      final rows = [
        textRow('05-08-26 SWIGGY 30.00', centerY: 100),
        textRow('CONTINUED DESCRIPTOR', centerY: 108),
        textRow('06-08-26 AMAZON 13.00', centerY: 115),
        textRow('07-08-26 UBER 20.00', centerY: 130),
      ];

      final region = locator.locate(rows).single;
      expect(region.anchorRows, hasLength(3));
      expect(
        region.rows,
        hasLength(4),
        reason: 'the continuation is in the band but is not an anchor',
      );
    });

    test('finds a table on every page it spans', () {
      final rows = [
        for (var page = 0; page < 3; page++) ...[
          textRow('PAGE HEADER', centerY: 40, page: page),
          textRow('05-08-26 SWIGGY 30.00', centerY: 100, page: page),
          textRow('06-08-26 AMAZON 13.00', centerY: 115, page: page),
          textRow('07-08-26 UBER 20.00', centerY: 130, page: page),
        ],
      ];

      final regions = locator.locate(rows);
      expect(regions, hasLength(3));
      expect(regions.map((r) => r.pageIndex), [0, 1, 2]);
    });

    test('a page with no table contributes nothing', () {
      final rows = [
        textRow('05-08-26 SWIGGY 30.00', centerY: 100),
        textRow('06-08-26 AMAZON 13.00', centerY: 115),
        textRow('07-08-26 UBER 20.00', centerY: 130),
        textRow('TERMS AND CONDITIONS', centerY: 40, page: 1),
        textRow('Nothing dated here at all', centerY: 60, page: 1),
      ];

      final regions = locator.locate(rows);
      expect(regions, hasLength(1));
      expect(regions.single.pageIndex, 0);
    });

    test('the anchor threshold is configurable', () {
      final rows = [
        textRow('05-08-26 SWIGGY 30.00', centerY: 100),
        textRow('06-08-26 AMAZON 13.00', centerY: 115),
      ];

      expect(locator.locate(rows), isEmpty);
      expect(const TableLocator(minAnchorRows: 2).locate(rows), hasLength(1));
    });
  });
}
