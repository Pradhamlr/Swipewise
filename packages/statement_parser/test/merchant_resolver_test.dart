import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

void main() {
  group('MerchantResolver', () {
    late MerchantResolver resolver;
    setUp(() => resolver = MerchantResolver());

    test('resolves a UPI narration to a merchant and an MCC', () {
      final match = resolver.resolve(
        'UPI/DR/655483690475/JioHotstar/YESB/hotstaronl/Sub',
      );

      expect(match.merchantId, 'jiohotstar');
      expect(match.mcc, 4899);
      expect(match.tags, contains('streaming'));
      expect(match.stage, ResolutionStage.exactCatalogue);
      expect(match.isConfident, isTrue);
    });

    test('resolves a card descriptor behind an aggregator prefix', () {
      final match = resolver.resolve('RAZORPAY*ZOMATO');
      expect(match.merchantId, 'zomato');
      expect(match.mcc, 5814);
    });

    test('a truncated descriptor still resolves, fuzzily', () {
      // Statements cut names off at the right edge.
      final match = resolver.resolve('AMAZON PAY INDIA PRIVAT');
      expect(match.merchantId, 'amazon');
      expect(
        match.stage,
        anyOf(ResolutionStage.exactCatalogue, ResolutionStage.fuzzyCatalogue),
      );
    });

    test('an exact hit is never overridden by a fuzzy one', () {
      // The ordering of the cascade is the design; this pins it.
      final match = resolver.resolve('UPI/DR/1234567890/OLA/YESB/ola123/Ride');
      expect(match.merchantId, 'ola');
      expect(match.stage, ResolutionStage.exactCatalogue);
      expect(match.confidence, 1);
    });

    test('similar-but-different merchants are not confused', () {
      // ZEPTO and ZOMATO share four letters. Getting this wrong would route a
      // grocery spend as food delivery and promise the wrong reward.
      expect(resolver.resolve('ZEPTO').merchantId, 'zepto');
      expect(resolver.resolve('ZOMATO').merchantId, 'zomato');
    });

    test('falls back to a category when no merchant matches', () {
      final match = resolver.resolve('HP PETROL PUMP KORAMANGALA FUEL');
      expect(match.mcc, 5541);
      expect(match.tags, contains('fuel'));
    });

    test('a family match reports lower confidence than an exact one', () {
      final family = resolver.resolve('SOME LOCAL TOLL PLAZA');
      expect(family.stage, ResolutionStage.family);
      expect(family.isConfident, isFalse);
      expect(family.mcc, 4784);
    });

    test('bank operations are classified, not matched', () {
      final atm = resolver.resolve('ATM CASH WDL 4455');
      expect(atm.stage, ResolutionStage.bankOperation);
      expect(atm.mcc, isNull, reason: 'an ATM withdrawal has no MCC');
    });

    test('an unknown merchant resolves to nothing rather than a guess', () {
      final match = resolver.resolve(
        'UPI/DR/123456789012/Kirana Store 42/YESB/abcd1234/Pay',
      );

      expect(match.isResolved, isFalse);
      expect(match.mcc, isNull);
      expect(match.confidence, 0);
    });

    test('a corner shop is not mistaken for a grocery chain', () {
      // Regression. "kirana" is the everyday word for a neighbourhood
      // grocery, and it used to fuzzy-match a chain's legal entity at 84%,
      // silently assigning that shop the chain's MCC.
      for (final shop in [
        'UPI/DR/123456789012/Kirana Store 42/YESB/abcd1234/Pay',
        'UPI/DR/123456789012/SRI KIRANA STORES/YESB/sks99/Pay',
        'KIRANA GENERAL STORE',
      ]) {
        expect(
          resolver.resolve(shop).isResolved,
          isFalse,
          reason: '"$shop" should go to the unknown queue',
        );
      }
    });

    test('a shared Indian name prefix is not treated as evidence', () {
      // Regression, found on real statements. INDIANC (a clearing house)
      // matched INDIANOIL 56 times because Jaro-Winkler adds a bonus for
      // four characters of shared prefix — and "INDIAN" prefixes a great many
      // unrelated Indian entities. Each false positive marked a transaction
      // as fuel, which every card excludes, silently zeroing real spending.
      for (final descriptor in ['INDIANC', 'INDIANR', 'INDIAN CLEARING']) {
        final match = resolver.resolve(descriptor);
        expect(
          match.merchantId,
          isNot('indian_oil'),
          reason: '"$descriptor" is not a petrol pump',
        );
      }
    });

    test('genuine truncation still matches', () {
      // Dropping the prefix bonus must not cost real matches.
      expect(resolver.resolve('SWIGGYL').merchantId, 'swiggy');
      expect(resolver.resolve('ZOMATOLTD').merchantId, 'zomato');
      expect(resolver.resolve('PVRINOX').merchantId, 'pvr');
    });

    test('a miss is preferred to a wrong answer', () {
      // The threshold errs toward missing on purpose: an unresolved
      // descriptor gets labelled once by the user, whereas a false positive
      // silently promises a reward that will never arrive.
      final tight = MerchantResolver(fuzzyThreshold: 0.99);
      expect(tight.resolve('SWIGY BANGALOR').isResolved, isFalse);
    });

    test('a null MCC is never invented', () {
      // The evaluator treats a null MCC as "no MCC rule fires". Guessing here
      // would promise a reward the user will not receive.
      final unknown = resolver.resolve('COMPLETELY UNKNOWN THING XYZQ');
      expect(unknown.mcc, isNull);
    });

    test('an abbreviation still matches fuzzily', () {
      // BLNKT is Blinkit with the vowels knocked out, which is exactly what
      // the fuzzy stage is for.
      final match = resolver.resolve(
        'UPI/DR/123456789012/BLNKT/YESB/blnkt99/Pay',
      );
      expect(match.merchantId, 'blinkit');
      expect(match.stage, ResolutionStage.fuzzyCatalogue);
      expect(match.confidence, greaterThan(0.9));
    });

    test('learns a user label and uses it next time', () {
      const descriptor = 'UPI/DR/123456789012/QQZX MART/YESB/qqzx77/Pay';
      expect(resolver.resolve(descriptor).isResolved, isFalse);

      resolver.learn('QQZX MART', 'blinkit');

      final match = resolver.resolve(descriptor);
      expect(match.merchantId, 'blinkit');
      expect(match.stage, ResolutionStage.userAlias);
      expect(match.mcc, 5411);
    });

    test('records what it matched against, for the why panel', () {
      final match = resolver.resolve('SWIGGY LIMITED');
      expect(match.matchedAgainst, isNotNull);
    });
  });

  group('catalogue integrity', () {
    test('every merchant has a plausible MCC and a unique id', () {
      final ids = <String>{};
      for (final merchant in merchantCatalog) {
        expect(
          ids.add(merchant.id),
          isTrue,
          reason: 'duplicate ${merchant.id}',
        );
        expect(merchant.mcc, greaterThanOrEqualTo(1000));
        expect(merchant.mcc, lessThanOrEqualTo(9999));
        expect(merchant.displayName, isNotEmpty);
      }
    });

    test('no alias is claimed by two merchants', () {
      final seen = <String, String>{};
      for (final merchant in merchantCatalog) {
        for (final alias in merchant.aliases) {
          final key = alias.toUpperCase();
          expect(
            seen.containsKey(key),
            isFalse,
            reason: '"$alias" claimed by ${seen[key]} and ${merchant.id}',
          );
          seen[key] = merchant.id;
        }
      }
    });
  });
}
