import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

void main() {
  group('jaro', () {
    test('identical strings score 1, disjoint score 0', () {
      expect(jaro('SWIGGY', 'SWIGGY'), 1);
      expect(jaro('ABC', 'XYZ'), 0);
    });

    test('empty input never throws', () {
      expect(jaro('', ''), 1);
      expect(jaro('SWIGGY', ''), 0);
      expect(jaro('', 'SWIGGY'), 0);
    });

    test('matches the textbook value for MARTHA/MARHTA', () {
      // The canonical worked example: two transposed characters.
      expect(jaro('MARTHA', 'MARHTA'), closeTo(0.944, 0.001));
    });

    test('a typo costs a little, not everything', () {
      expect(jaro('ZOMATO', 'ZOMAOT'), greaterThan(0.9));
    });
  });

  group('jaroWinkler', () {
    test('rewards a shared prefix over a shared suffix', () {
      // Statements truncate from the right, so a shared start is the stronger
      // signal. AMAZON... should beat ...INDIA.
      final prefixMatch = jaroWinkler('AMAZON PAY', 'AMAZON PAY INDIA');
      final suffixMatch = jaroWinkler('FLIPKART INDIA', 'AMAZON PAY INDIA');
      expect(prefixMatch, greaterThan(suffixMatch));
    });

    test('never scores below plain Jaro', () {
      for (final pair in [
        ['SWIGGY', 'SWIGGY BANGALORE'],
        ['ZOMATO', 'ZOMATO LTD'],
        ['UBER', 'OLA'],
      ]) {
        expect(
          jaroWinkler(pair[0], pair[1]),
          greaterThanOrEqualTo(jaro(pair[0], pair[1])),
        );
      }
    });

    test('stays within 0..1', () {
      expect(jaroWinkler('AMAZON', 'AMAZON'), 1);
      expect(jaroWinkler('AMAZONAMAZON', 'AMAZON'), lessThanOrEqualTo(1));
    });
  });

  group('trigramSimilarity', () {
    test('survives reordered words where Jaro-Winkler does not', () {
      // The reason both measures exist.
      expect(trigramSimilarity('BIG BASKET', 'BASKET BIG'), greaterThan(0.5));
      expect(jaroWinkler('BIG BASKET', 'BASKET BIG'), lessThan(0.75));
    });

    test('short and empty strings do not throw', () {
      expect(trigramSimilarity('', 'SWIGGY'), 0);
      expect(trigramSimilarity('A', 'A'), 1);
    });
  });

  group('merchantSimilarity', () {
    test('separates real merchants from unrelated ones', () {
      expect(
        merchantSimilarity('SWIGGY BANGALORE', 'SWIGGY'),
        greaterThan(0.7),
      );
      expect(merchantSimilarity('ZOMATO', 'SWIGGY'), lessThan(0.5));
    });

    test('is case and whitespace insensitive', () {
      expect(merchantSimilarity('  swiggy ', 'SWIGGY'), 1);
    });
  });
}
