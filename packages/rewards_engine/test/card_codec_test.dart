import 'dart:io';

import 'package:rewards_engine/rewards_engine.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The shipped rule bundle lives with the app, but it is *data*, so the engine
/// is what proves it decodes and behaves. These are the golden tests the spec
/// calls for: a real card definition in, a known reward out. A bad rate edit
/// fails here rather than on a device.
///
/// `yaml` is a dev-dependency only — the engine itself stays dependency-free
/// and takes plain maps.
Map<String, dynamic> loadCard(String file) {
  final source = File('../../app/assets/rules/$file').readAsStringSync();
  final doc = loadYaml(source) as YamlMap;
  return <String, dynamic>{
    for (final entry in doc.entries) entry.key.toString(): entry.value,
  };
}

SpendContext spend(
  int rupees, {
  int? mcc,
  Channel channel = Channel.online,
  Set<String> tags = const {},
}) {
  return SpendContext(
    amountPaise: rupees * 100,
    date: DateTime.utc(2026, 8, 20),
    channel: channel,
    mcc: mcc,
    tags: tags,
  );
}

void main() {
  group('every shipped card', () {
    const files = [
      'sbi_cashback.yaml',
      'axis_ace.yaml',
      'amazon_pay_icici.yaml',
    ];

    for (final file in files) {
      test('$file decodes and carries its provenance', () {
        final card = cardFromMap(loadCard(file));

        expect(card.id, isNotEmpty);
        expect(card.name, isNotEmpty);
        expect(card.rules, isNotEmpty);

        // No card without a citation ships. This is the check that stops an
        // invented rate reaching a device.
        expect(card.sourceUrl, startsWith('https://'));
        expect(card.retrievedOn.year, greaterThanOrEqualTo(2024));

        // Every bucket a rule consumes must actually exist, or the cap would
        // silently never bind.
        for (final rule in card.rules) {
          for (final bucketId in rule.consumes) {
            expect(
              card.bucket(bucketId),
              isNotNull,
              reason: '${card.id}: rule "${rule.id}" consumes unknown '
                  'bucket "$bucketId"',
            );
          }
        }
      });
    }
  });

  group('CASHBACK SBI Card', () {
    late RewardCard card;
    setUp(() => card = cardFromMap(loadCard('sbi_cashback.yaml')));

    test('pays 5% online and 1% offline', () {
      expect(
        marginalReward(card: card, spend: spend(1000)).rupeesPaise,
        5000,
      );
      expect(
        marginalReward(
          card: card,
          spend: spend(1000, channel: Channel.offline),
        ).rupeesPaise,
        1000,
      );
    });

    test('clips online cashback at the 2,000 per-cycle ceiling', () {
      // 5% of 50,000 would be 2,500; the online bucket stops it at 2,000.
      final result = marginalReward(card: card, spend: spend(50000));
      expect(result.rupeesPaise, 200000);
      expect(result.explanation, contains('Online cashback'));
    });

    test('the shared aggregate ceiling binds across both rules', () {
      // Offline earning is capped at 2,000 of its own, but if the overall
      // 4,000 is nearly spent the aggregate binds first. Here 3,900 of the
      // overall is gone, so only 100 remains no matter which rule fires.
      final result = marginalReward(
        card: card,
        spend: spend(50000, channel: Channel.offline),
        state: const CycleState({'overall_cap': 390000}),
      );

      expect(result.rupeesPaise, 10000);
      final binding = result.buckets.firstWhere((b) => b.clamped);
      expect(binding.bucketId, 'overall_cap');
    });

    test('fuel earns nothing', () {
      final result = marginalReward(
        card: card,
        spend: spend(3000, tags: {'fuel'}),
      );
      expect(result.isZero, isTrue);
    });
  });

  group('Axis Bank ACE', () {
    late RewardCard card;
    setUp(() => card = cardFromMap(loadCard('axis_ace.yaml')));

    test('pays 4% on Swiggy and 1.5% elsewhere', () {
      expect(
        marginalReward(card: card, spend: spend(1000, tags: {'swiggy'}))
            .rupeesPaise,
        4000,
      );
      expect(
        marginalReward(card: card, spend: spend(1000)).rupeesPaise,
        1500,
      );
    });

    test('utility needs both the MCC and Google Pay', () {
      final onGooglePay = marginalReward(
        card: card,
        spend: spend(1000, mcc: 4814, tags: {'google_pay'}),
      );
      expect(onGooglePay.ruleId, 'utility_googlepay');
      expect(onGooglePay.rupeesPaise, 5000);

      // Same spend elsewhere drops to the base rate, exactly as the T&C says.
      final elsewhere = marginalReward(
        card: card,
        spend: spend(1000, mcc: 4814),
      );
      expect(elsewhere.ruleId, 'base');
    });

    test('the 5% and 4% rules share one 500 bucket', () {
      // The headline structure. Spending the bucket via utilities leaves
      // nothing for Swiggy, and the card falls back to its uncapped 1.5%.
      const exhausted = CycleState({'accelerated_cap': 50000});

      final swiggy = marginalReward(
        card: card,
        spend: spend(1000, tags: {'swiggy'}),
        state: exhausted,
      );

      expect(swiggy.ruleId, 'base');
      expect(swiggy.rupeesPaise, 1500);
    });

    test('the base rate is genuinely uncapped', () {
      final result = marginalReward(card: card, spend: spend(200000));
      expect(result.rupeesPaise, 300000); // 1.5% of 2,00,000
      expect(result.buckets, isEmpty);
    });

    test('rent and gold earn nothing', () {
      for (final tag in ['rent', 'gold', 'insurance', 'wallet_load']) {
        expect(
          marginalReward(card: card, spend: spend(5000, tags: {tag})).isZero,
          isTrue,
          reason: '$tag should be excluded',
        );
      }
    });
  });

  group('Amazon Pay ICICI', () {
    late RewardCard card;
    setUp(() => card = cardFromMap(loadCard('amazon_pay_icici.yaml')));

    test('converts points to rupees at the declared value', () {
      // 5% of 1,000 is 50 points, worth ₹1 each.
      final result = marginalReward(
        card: card,
        spend: spend(1000, tags: {'amazon'}),
      );
      expect(result.ruleId, 'amazon_prime');
      expect(result.rupeesPaise, 5000);
    });

    test('has no caps, so large spends keep earning', () {
      final result = marginalReward(card: card, spend: spend(200000));
      expect(result.rupeesPaise, 200000); // 1% of 2,00,000
    });
  });

  group('routing across the real bundle', () {
    late List<RewardCard> cards;
    setUp(() {
      cards = [
        cardFromMap(loadCard('sbi_cashback.yaml')),
        cardFromMap(loadCard('axis_ace.yaml')),
        cardFromMap(loadCard('amazon_pay_icici.yaml')),
      ];
    });

    test('a small online spend goes to the 5% card', () {
      final ranking = rankCards(cards: cards, spend: spend(1000));
      expect(ranking.winner!.cardId, 'sbi-cashback');
      expect(ranking.winner!.rupeesPaise, 5000);
    });

    test('a large spend routes away once the 5% cap is nearly gone', () {
      // The edge case the project exists for, now on real published terms
      // rather than invented ones. SBI has ₹50 of online headroom left, so
      // its headline 5% is worth ₹50 on a ₹20,000 spend. Axis's uncapped
      // 1.5% is worth ₹300 and wins; ICICI's uncapped 1% is worth ₹200.
      final ranking = rankCards(
        cards: cards,
        spend: spend(20000),
        states: const {
          'sbi-cashback': CycleState({'online_cap': 195000}),
        },
      );

      expect(ranking.winner!.cardId, 'axis-ace');
      expect(ranking.winner!.rupeesPaise, 30000);
      expect(ranking.runnerUp!.cardId, 'amazon-pay-icici');

      final sbi = ranking.ranked.firstWhere((r) => r.cardId == 'sbi-cashback');
      expect(sbi.rupeesPaise, 5000, reason: 'clamped to its remaining ₹50');
      expect(sbi.effectiveRate, closeTo(0.0025, 1e-6));
    });

    test('the same spend goes to SBI when the cap is fresh', () {
      // Same cards, same amount, opposite answer — the recommendation is a
      // function of cycle state, not of the headline rates.
      final ranking = rankCards(cards: cards, spend: spend(20000));

      expect(ranking.winner!.cardId, 'sbi-cashback');
      expect(ranking.winner!.rupeesPaise, 100000); // 5% of 20,000
    });
  });
}
