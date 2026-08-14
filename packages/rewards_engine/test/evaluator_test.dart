import 'package:rewards_engine/rewards_engine.dart';
import 'package:test/test.dart';

// Fictional cards. These are test fixtures, not reward data — no rate here is
// claimed to match any real product, which is exactly why they can be written
// inline. Shipped cards live in the rules bundle with a source URL.

final _dining = DateTime.utc(2026, 8, 15);

SpendContext spend(
  int paise, {
  int? mcc,
  Channel channel = Channel.online,
  Set<String> tags = const {},
}) {
  return SpendContext(
    amountPaise: paise,
    date: _dining,
    channel: channel,
    mcc: mcc,
    tags: tags,
  );
}

/// 5% online on dining/grocery, capped, with a 1% base. The overall cap is
/// shared by both rules — the structure that a cap-as-a-field-on-a-rule schema
/// cannot express.
RewardCard acceleratedCard() {
  return RewardCard(
    id: 'accelerated',
    name: 'Test Accelerated',
    issuer: 'test',
    buckets: const [
      CapBucket(
        id: 'online_cap',
        limitPaise: 150000,
        unit: RewardUnit.cashback,
        label: 'Online cashback',
      ),
      CapBucket(
        id: 'overall_cap',
        limitPaise: 200000,
        unit: RewardUnit.cashback,
        label: 'Overall cashback',
      ),
    ],
    rules: [
      const RewardRule(
        id: 'online_accelerated',
        when: AllOf([
          ChannelIs(Channel.online),
          MccIn({5814, 5411}),
          NotPredicate(MerchantIn({'rent', 'wallet_load'})),
        ]),
        rate: 0.05,
        unit: RewardUnit.cashback,
        consumes: ['online_cap', 'overall_cap'],
        description: '5% online dining and grocery',
      ),
      const RewardRule(
        id: 'base',
        when: Always(),
        rate: 0.01,
        unit: RewardUnit.cashback,
        consumes: ['overall_cap'],
        description: '1% on everything else',
      ),
    ],
    excludedMccs: const {6513},
    excludedTags: const {'fuel'},
    sourceUrl: 'https://example.invalid/terms',
    retrievedOn: DateTime.utc(2026, 8, 15),
    validFrom: DateTime.utc(2026),
  );
}

/// Flat 1.5%, no caps at all.
RewardCard flatCard() {
  return RewardCard(
    id: 'flat',
    name: 'Test Flat',
    issuer: 'test',
    rules: const [
      RewardRule(
        id: 'flat',
        when: Always(),
        rate: 0.015,
        unit: RewardUnit.cashback,
        description: '1.5% on everything, uncapped',
      ),
    ],
    sourceUrl: 'https://example.invalid/terms',
    retrievedOn: DateTime.utc(2026, 8, 15),
    validFrom: DateTime.utc(2026),
  );
}

void main() {
  group('marginalReward', () {
    test('the accelerated rule fires when its predicate holds', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814),
      );

      expect(result.ruleId, 'online_accelerated');
      expect(result.rupeesPaise, 4000); // 5% of 800
      expect(result.effectiveRate, closeTo(0.05, 1e-9));
    });

    test('falls to the base rate when the predicate does not hold', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814, channel: Channel.offline),
      );

      expect(result.ruleId, 'base');
      expect(result.rupeesPaise, 800);
    });

    test('a missing MCC does not fire MCC rules', () {
      // Guessing an MCC would inflate the reward the user is promised.
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000),
      );
      expect(result.ruleId, 'base');
    });

    test('a partially full bucket clamps the payout', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814),
        state: const CycleState({'online_cap': 148000}),
      );

      // 5% of 800 is 40, but only 20 of headroom remains.
      expect(result.ruleId, 'online_accelerated');
      expect(result.rupeesPaise, 2000);
      expect(result.effectiveRate, closeTo(0.025, 1e-9));
      expect(result.explanation, contains('clipped'));

      final binding = result.buckets.firstWhere((b) => b.clamped);
      expect(binding.bucketId, 'online_cap');
      expect(binding.remainingPaise, 0);
    });

    test('an exhausted bucket falls through to the next matching rule', () {
      // The behaviour that separates an evaluator from a lookup table.
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814),
        state: const CycleState({'online_cap': 150000}),
      );

      expect(result.ruleId, 'base');
      expect(result.rupeesPaise, 800);
      expect(result.effectiveRate, closeTo(0.01, 1e-9));
    });

    test('a shared cap consumed by one rule constrains the other', () {
      // overall_cap is referenced by both rules. Exhaust it and even the base
      // rate pays nothing.
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814),
        state: const CycleState({
          'online_cap': 150000,
          'overall_cap': 200000,
        }),
      );

      expect(result.isZero, isTrue);
      expect(result.ruleId, isNull);
    });

    test('excluded MCCs earn nothing', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(2500000, mcc: 6513),
      );
      expect(result.isZero, isTrue);
      expect(result.explanation, contains('excluded'));
    });

    test('excluded tags earn nothing', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(300000, mcc: 5541, tags: {'fuel'}),
      );
      expect(result.isZero, isTrue);
      expect(result.explanation, contains('fuel'));
    });

    test('a not-predicate blocks an otherwise matching rule', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5411, tags: {'rent'}),
      );
      expect(result.ruleId, 'base');
    });

    test('reports how much more spend the accelerated rate survives', () {
      final result = marginalReward(
        card: acceleratedCard(),
        spend: spend(80000, mcc: 5814),
        state: const CycleState({'online_cap': 145000}),
      );

      // 50 of headroom at 5% is 1,000 of further spend.
      expect(result.spendUntilRateDropsPaise, 100000);
    });

    test('points are converted to rupees at the card rate', () {
      final pointsCard = RewardCard(
        id: 'points',
        name: 'Test Points',
        issuer: 'test',
        pointValuePaise: 25,
        rules: const [
          RewardRule(
            id: 'earn',
            when: Always(),
            rate: 0.02,
            unit: RewardUnit.points,
          ),
        ],
        sourceUrl: 'https://example.invalid/terms',
        retrievedOn: DateTime.utc(2026, 8, 15),
        validFrom: DateTime.utc(2026),
      );

      // 1,000 spend at 2 points per 100 is 20 points, worth 25 paise each.
      final result = marginalReward(
        card: pointsCard,
        spend: spend(100000),
      );
      expect(result.rupeesPaise, 500);
    });
  });

  group('rankCards', () {
    test('ranks in rupees and exposes the runner-up', () {
      final ranking = rankCards(
        cards: [flatCard(), acceleratedCard()],
        spend: spend(80000, mcc: 5814),
      );

      expect(ranking.winner!.cardId, 'accelerated');
      expect(ranking.runnerUp!.cardId, 'flat');
      expect(ranking.advantagePaise, 4000 - 1200);
    });

    test('routes away from the 5% card when its cap is nearly gone', () {
      // The edge case the whole project is built to handle: a large spend
      // going to the *lower* headline rate because the better rate has no
      // room left.
      final ranking = rankCards(
        cards: [acceleratedCard(), flatCard()],
        spend: spend(1500000, mcc: 5814),
        states: const {
          'accelerated': CycleState({'online_cap': 145000}),
        },
      );

      expect(ranking.winner!.cardId, 'flat');
      expect(ranking.winner!.rupeesPaise, 22500); // 1.5% of 15,000
      expect(ranking.runnerUp!.rupeesPaise, 5000); // clamped to headroom
    });

    test('an empty card list ranks to nothing rather than throwing', () {
      final ranking = rankCards(cards: [], spend: spend(80000));
      expect(ranking.winner, isNull);
      expect(ranking.advantagePaise, 0);
    });
  });

  group('findRecommendationFlip', () {
    test('finds the amount at which the recommendation changes', () {
      // Accelerated pays 5% up to 50 of remaining headroom, so it is capped at
      // 50. Flat pays 1.5% forever and overtakes once 1.5% exceeds 50, which
      // is at a spend of 3,333.33.
      final flip = findRecommendationFlip(
        cards: [acceleratedCard(), flatCard()],
        spend: spend(80000, mcc: 5814),
        states: const {
          'accelerated': CycleState({'online_cap': 145000}),
        },
      );

      expect(flip, isNotNull);
      expect(flip, greaterThan(333000));
      expect(flip, lessThan(334500));
    });

    test('returns null when the winner never changes', () {
      final flip = findRecommendationFlip(
        cards: [flatCard()],
        spend: spend(80000),
      );
      expect(flip, isNull);
    });
  });
}
