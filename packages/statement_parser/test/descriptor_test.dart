import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

void main() {
  group('UPI narrations', () {
    test('pulls the payee out and leaves the reference behind', () {
      final parsed = parseDescriptor(
        'UPI/DR/655483690475/JioHotstar/YESB/hotstaronl/Sub',
      );

      expect(parsed.kind, DescriptorKind.upi);
      expect(parsed.best, 'JIOHOTSTAR');
      expect(parsed.reference, '655483690475');
      expect(parsed.handle, 'hotstaronl');
    });

    test('the reference never becomes a matching candidate', () {
      // A twelve-digit number shares trigrams with anything numeric and would
      // drag the fuzzy matcher around.
      final parsed = parseDescriptor(
        'UPI/DR/655483690475/JioHotstar/YESB/hotstaronl/Sub',
      );
      expect(parsed.candidates, isNot(contains('655483690475')));
      for (final candidate in parsed.candidates) {
        expect(RegExp(r'^\d+$').hasMatch(candidate), isFalse);
      }
    });

    test('drops the four-letter bank code', () {
      final parsed = parseDescriptor(
        'UPI/DR/123456789012/Zomato/YESB/zomato123/Food',
      );
      expect(parsed.candidates, isNot(contains('YESB')));
      expect(parsed.best, 'ZOMATO');
    });

    test('a meaningless handle is not offered as a name', () {
      // q438734900 is a bank-generated handle, not a merchant.
      final parsed = parseDescriptor(
        'UPI/DR/618891012262/CHANGAMP/YESB/q438734900/UPI',
      );
      expect(parsed.best, 'CHANGAMP');
      expect(parsed.candidates, isNot(contains('q438734900')));
    });

    test('offers the handle when it is the readable part', () {
      final parsed = parseDescriptor(
        'UPI/DR/123456789012/9876543210/YESB/bigbasket/Groceries',
      );
      expect(parsed.candidates, contains('BIGBASKET'));
    });
  });

  group('card descriptors', () {
    test('strips aggregator prefixes', () {
      expect(parseDescriptor('RAZORPAY*ZOMATO').best, 'ZOMATO');
      expect(parseDescriptor('PAYU*BOOKMYSHOW BLR').best, 'BOOKMYSHOW BLR');
      expect(parseDescriptor('PHONEPE*SWIGGY').best, 'SWIGGY');
    });

    test('leaves a star alone when the prefix is not an aggregator', () {
      // Not every star is an acquirer prefix.
      expect(parseDescriptor('STAR*BUCKS').best, contains('STAR'));
    });

    test('drops corporate and location noise', () {
      expect(
        parseDescriptor('AMAZON PAY INDIA PRIVAT').best,
        'AMAZON PAY',
      );
      expect(parseDescriptor('SWIGGY PVT LTD').best, 'SWIGGY');
    });
  });

  group('bank operations', () {
    test('recognises things that are not merchants at all', () {
      expect(
        parseDescriptor('ATM CASH WDL 1234').kind,
        DescriptorKind.bankOperation,
      );
      expect(parseDescriptor('ATM CASH WDL 1234').best, 'atm');
      expect(parseDescriptor('INT.PD:01-04-2026').best, 'interest');
      expect(parseDescriptor('SMS CHARGES FOR Q1').best, 'bank_charge');
    });

    test('a salary credit is classified, not fuzzy-matched', () {
      final parsed = parseDescriptor('NEFT CR SALARY JULY');
      expect(parsed.kind, DescriptorKind.bankOperation);
      expect(parsed.best, anyOf('salary', 'interest'));
    });
  });

  test('empty input is unknown rather than an exception', () {
    final parsed = parseDescriptor('   ');
    expect(parsed.kind, DescriptorKind.unknown);
    expect(parsed.best, isNull);
  });
}
