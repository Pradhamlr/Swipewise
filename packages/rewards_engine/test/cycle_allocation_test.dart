import 'dart:math';

import 'package:rewards_engine/rewards_engine.dart';
import 'package:test/test.dart';

final _date = DateTime.utc(2026, 8, 20);

SpendContext spend(int rupees) =>
    SpendContext(amountPaise: rupees * 100, date: _date);

RewardCard card({
  required String id,
  required double rate,
  int? capRupees,
  int? milestoneThresholdRupees,
  int? milestoneGrantRupees,
}) {
  return RewardCard(
    id: id,
    name: id,
    issuer: 'test',
    buckets: [
      if (capRupees != null)
        CapBucket(
          id: '${id}_cap',
          limitPaise: capRupees * 100,
          unit: RewardUnit.cashback,
          label: '$id cap',
        ),
    ],
    rules: [
      RewardRule(
        id: '${id}_base',
        when: const Always(),
        rate: rate,
        unit: RewardUnit.cashback,
        consumes: [if (capRupees != null) '${id}_cap'],
      ),
    ],
    milestones: [
      if (milestoneThresholdRupees != null && milestoneGrantRupees != null)
        Milestone(
          id: '${id}_milestone',
          thresholdPaise: milestoneThresholdRupees * 100,
          grantPaise: milestoneGrantRupees * 100,
        ),
    ],
    sourceUrl: 'https://example.invalid/terms',
    retrievedOn: DateTime.utc(2026, 8, 15),
    validFrom: DateTime.utc(2026),
  );
}

void main() {
  group('the case the project exists for', () {
    // Card A pays less per transaction but grants ₹500 at ₹10,000 of spend.
    // Card B pays more per transaction and grants nothing.
    final milestoneCard = card(
      id: 'milestone',
      rate: 0.01,
      milestoneThresholdRupees: 10000,
      milestoneGrantRupees: 500,
    );
    final flatCard = card(id: 'flat', rate: 0.02);
    final cards = [milestoneCard, flatCard];
    final spends = [for (var i = 0; i < 10; i++) spend(1000)];

    test('greedy takes the better rate and misses the milestone', () {
      final greedy = greedyAllocate(spends: spends, cards: cards);

      // Every transaction goes to the 2% card: ₹200, no milestone.
      expect(greedy.totalValuePaise, 20000);
      expect(
        greedy.perCard.firstWhere((c) => c.cardId == 'milestone').spendPaise,
        0,
      );
    });

    test('the allocator gives up rate to cross the threshold', () {
      final allocated = allocateCycle(spends: spends, cards: cards);

      // 1% of ₹10,000 is ₹100, plus the ₹500 grant: ₹600 against greedy's
      // ₹200. Three times the value, from the same spending.
      expect(allocated.totalValuePaise, 60000);
      expect(
        allocated.perCard
            .firstWhere((c) => c.cardId == 'milestone')
            .milestonesEarned,
        ['milestone_milestone'],
      );
    });

    test('and brute force confirms that is the true optimum', () {
      final best = bruteForceAllocate(spends: spends, cards: cards);
      final allocated = allocateCycle(spends: spends, cards: cards);
      expect(allocated.totalValuePaise, best.totalValuePaise);
    });

    test('leakage is reported against the achievable allocation', () {
      final greedy = greedyAllocate(spends: spends, cards: cards);
      final allocated = allocateCycle(spends: spends, cards: cards);

      expect(allocated.gainOver(greedy), 40000);
      expect(allocated.leakageOf(greedy), closeTo(2 / 3, 1e-9));
    });
  });

  group('evaluateAllocation', () {
    test('replays spends in order, so caps fill as they would in life', () {
      // A ₹100 cap at 10%: the first ₹1,000 earns fully, the rest earns
      // nothing. Scoring transactions independently would report ₹200.
      final capped = card(id: 'capped', rate: 0.1, capRupees: 100);
      final spends = [spend(1000), spend(1000)];

      final result = evaluateAllocation(
        spends: spends,
        cards: [capped],
        assignment: [0, 0],
      );

      expect(result.totalValuePaise, 10000);
      expect(result.effectiveRate, closeTo(0.05, 1e-9));
    });

    test('milestones count spend, not reward', () {
      final withMilestone = card(
        id: 'm',
        rate: 0,
        milestoneThresholdRupees: 500,
        milestoneGrantRupees: 250,
      );

      final result = evaluateAllocation(
        spends: [spend(500)],
        cards: [withMilestone],
        assignment: [0],
      );

      expect(result.perCard.single.rewardPaise, 0);
      expect(result.perCard.single.milestonePaise, 25000);
    });

    test('a threshold missed by one rupee grants nothing', () {
      final withMilestone = card(
        id: 'm',
        rate: 0,
        milestoneThresholdRupees: 500,
        milestoneGrantRupees: 250,
      );

      final result = evaluateAllocation(
        spends: [spend(499)],
        cards: [withMilestone],
        assignment: [0],
      );
      expect(result.totalValuePaise, 0);
    });
  });

  group(
      'property: allocation is never worse than greedy, never better than '
      'the true optimum', () {
    // The invariant the spec calls out, checked against brute force rather
    // than against another heuristic — otherwise it only proves two guesses
    // agree. Instances are kept small enough to enumerate exhaustively.
    test('holds over 200 random instances', () {
      final random = Random(20260815);
      var strictlyBetterThanGreedy = 0;
      var matchedOptimum = 0;

      for (var trial = 0; trial < 200; trial++) {
        final cardCount = 2 + random.nextInt(2);
        final cards = [
          for (var c = 0; c < cardCount; c++)
            card(
              id: 'c$c',
              rate: (1 + random.nextInt(50)) / 1000,
              capRupees: random.nextBool() ? 50 + random.nextInt(400) : null,
              milestoneThresholdRupees:
                  random.nextBool() ? 1000 + random.nextInt(6000) : null,
              milestoneGrantRupees: 100 + random.nextInt(900),
            ),
        ];

        final spendCount = 2 + random.nextInt(6);
        final spends = [
          for (var s = 0; s < spendCount; s++)
            spend(100 + random.nextInt(2000)),
        ];

        final greedy = greedyAllocate(spends: spends, cards: cards);
        final allocated = allocateCycle(spends: spends, cards: cards);
        final optimum = bruteForceAllocate(spends: spends, cards: cards);

        expect(
          allocated.totalValuePaise,
          greaterThanOrEqualTo(greedy.totalValuePaise),
          reason: 'trial $trial: allocation fell below greedy',
        );
        expect(
          allocated.totalValuePaise,
          lessThanOrEqualTo(optimum.totalValuePaise),
          reason: 'trial $trial: allocation beat the true optimum, so the '
              'evaluator disagrees with itself',
        );

        if (allocated.totalValuePaise > greedy.totalValuePaise) {
          strictlyBetterThanGreedy++;
        }
        if (allocated.totalValuePaise == optimum.totalValuePaise) {
          matchedOptimum++;
        }
      }

      // Not assertions about quality so much as a guard against a vacuous
      // test: if the allocator never beat greedy, the invariant would hold
      // trivially and prove nothing.
      expect(
        strictlyBetterThanGreedy,
        greaterThan(0),
        reason: 'the allocator never improved on greedy — test is vacuous',
      );
      expect(
        matchedOptimum,
        greaterThan(150),
        reason: 'the heuristic reached the true optimum in only '
            '$matchedOptimum of 200 instances',
      );
    });
  });

  group('edges', () {
    test('no spends allocates to nothing', () {
      final result = allocateCycle(spends: [], cards: [card(id: 'a', rate: 1)]);
      expect(result.totalValuePaise, 0);
    });

    test('brute force refuses instances it cannot enumerate', () {
      expect(
        () => bruteForceAllocate(
          spends: [for (var i = 0; i < 40; i++) spend(100)],
          cards: [card(id: 'a', rate: 0.01), card(id: 'b', rate: 0.02)],
        ),
        throwsArgumentError,
      );
    });
  });
}
