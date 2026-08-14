import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Money.parse', () {
    test('reads plain and fractional amounts', () {
      expect(Money.parse('800').paise, 80000);
      expect(Money.parse('800.00').paise, 80000);
      expect(Money.parse('800.5').paise, 80050);
      expect(Money.parse('0.07').paise, 7);
    });

    test('reads Indian digit grouping', () {
      expect(Money.parse('1,23,456.78').paise, 12345678);
      expect(Money.parse('1,234.56').paise, 123456);
    });

    test('reads a leading minus as a debit', () {
      final amount = Money.parse('-1234.50');
      expect(amount.paise, -123450);
      expect(amount.isDebit, isTrue);
      expect(amount.isCredit, isFalse);
    });

    test('tolerates surrounding whitespace', () {
      expect(Money.parse('  42.00 ').paise, 4200);
    });

    test('rejects issuer presentation quirks rather than guessing', () {
      // Dr/Cr markers, trailing minus and parenthesised negatives are all
      // real formats, but deciding what they mean is normalization's job.
      for (final input in ['800.00 Dr', '800.00-', '(800.00)', '', 'abc']) {
        expect(
          () => Money.parse(input),
          throwsFormatException,
          reason: 'should not silently accept "$input"',
        );
      }
    });

    test('rejects more than two decimal places', () {
      expect(() => Money.parse('1.234'), throwsFormatException);
    });
  });

  group('Money', () {
    test('round trips through its decimal string', () {
      for (final paise in [0, 7, 100, -123450, 999999]) {
        final money = Money(paise);
        expect(Money.parse(money.toDecimalString()), equals(money));
      }
    });

    test('pads the fractional part', () {
      expect(const Money(80050).toDecimalString(), '800.50');
      expect(const Money(7).toDecimalString(), '0.07');
      expect(const Money(-7).toDecimalString(), '-0.07');
    });

    test('adds without floating point drift', () {
      // 0.1 + 0.2 in doubles is famously not 0.3.
      final sum = Money.parse('0.10') + Money.parse('0.20');
      expect(sum, equals(Money.parse('0.30')));
    });

    test('compares and negates', () {
      expect(Money.parse('-800') < Money.zero, isTrue);
      expect(Money.parse('800').negated, equals(Money.parse('-800')));
      expect(Money.parse('-800').absolute, equals(Money.parse('800')));
    });
  });
}
