import 'package:rewards_engine/src/evaluator.dart';
import 'package:rewards_engine/src/model/rules.dart';
import 'package:rewards_engine/src/model/spend.dart';

/// What one card earned over a cycle under a given allocation.
class CardCycleResult {
  const CardCycleResult({
    required this.cardId,
    required this.spendPaise,
    required this.rewardPaise,
    required this.milestonePaise,
    required this.transactionCount,
    required this.milestonesEarned,
  });

  final String cardId;
  final int spendPaise;

  /// Sum of per-transaction rewards, cap clamping already applied.
  final int rewardPaise;

  /// Lump sums from crossing spend thresholds.
  final int milestonePaise;

  final int transactionCount;
  final List<String> milestonesEarned;

  int get totalPaise => rewardPaise + milestonePaise;
}

/// An assignment of every spend to a card, and what it is worth.
class CycleAllocation {
  const CycleAllocation({
    required this.assignment,
    required this.perCard,
    required this.totalValuePaise,
    required this.totalSpendPaise,
  });

  /// Index into the card list, one per spend, in spend order.
  final List<int> assignment;

  final List<CardCycleResult> perCard;

  /// Rewards plus milestone grants, across every card.
  final int totalValuePaise;

  final int totalSpendPaise;

  /// Reward as a fraction of spend.
  double get effectiveRate =>
      totalSpendPaise == 0 ? 0 : totalValuePaise / totalSpendPaise;

  /// Value this allocation captures that [other] does not.
  int gainOver(CycleAllocation other) =>
      totalValuePaise - other.totalValuePaise;

  /// The headline figure: the fraction of achievable value that [other]
  /// leaves unclaimed relative to this allocation.
  double leakageOf(CycleAllocation other) {
    if (totalValuePaise <= 0) return 0;
    final missed = totalValuePaise - other.totalValuePaise;
    return missed <= 0 ? 0 : missed / totalValuePaise;
  }
}

/// Score a specific assignment.
///
/// Spends are replayed in order, because the evaluator is stateful: the tenth
/// dining transaction of a cycle is worth less than the first once a bucket is
/// filling. Any allocator that scores transactions independently would get
/// this wrong, which is precisely the mistake this whole layer exists to avoid.
CycleAllocation evaluateAllocation({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  required List<int> assignment,
  Map<String, CycleState> initialStates = const {},
}) {
  final states = <String, CycleState>{
    for (final card in cards)
      card.id: initialStates[card.id] ?? const CycleState.empty(),
  };
  final reward = <String, int>{for (final card in cards) card.id: 0};
  final spent = <String, int>{for (final card in cards) card.id: 0};
  final count = <String, int>{for (final card in cards) card.id: 0};

  for (var i = 0; i < spends.length; i++) {
    final card = cards[assignment[i]];
    final result = marginalReward(
      card: card,
      spend: spends[i],
      state: states[card.id]!,
    );

    reward[card.id] = reward[card.id]! + result.rupeesPaise;
    spent[card.id] = spent[card.id]! + spends[i].amountPaise;
    count[card.id] = count[card.id]! + 1;

    for (final bucket in result.buckets) {
      states[card.id] = states[card.id]!
          .withConsumption([bucket.bucketId], bucket.appliedPaise);
    }
  }

  final perCard = <CardCycleResult>[];
  var total = 0;
  var totalSpend = 0;

  for (final card in cards) {
    final cardSpend = spent[card.id]!;
    var milestoneValue = 0;
    final earned = <String>[];

    for (final milestone in card.milestones) {
      if (cardSpend >= milestone.thresholdPaise) {
        milestoneValue += milestone.grantPaise;
        earned.add(milestone.id);
      }
    }

    perCard.add(
      CardCycleResult(
        cardId: card.id,
        spendPaise: cardSpend,
        rewardPaise: reward[card.id]!,
        milestonePaise: milestoneValue,
        transactionCount: count[card.id]!,
        milestonesEarned: earned,
      ),
    );

    total += reward[card.id]! + milestoneValue;
    totalSpend += cardSpend;
  }

  return CycleAllocation(
    assignment: assignment,
    perCard: perCard,
    totalValuePaise: total,
    totalSpendPaise: totalSpend,
  );
}

/// Route each transaction to whichever card pays most *for that transaction*.
///
/// This is what a careful person does by hand, and what every comparable app
/// does. It is myopic in exactly one way: it cannot spend a little now to earn
/// a lot later, so it will never top up a card to reach a milestone and will
/// happily exhaust a shared cap on small transactions that a cheaper card
/// would have handled equally well.
CycleAllocation greedyAllocate({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  Map<String, CycleState> initialStates = const {},
}) {
  final states = <String, CycleState>{
    for (final card in cards)
      card.id: initialStates[card.id] ?? const CycleState.empty(),
  };
  final assignment = List<int>.filled(spends.length, 0);

  for (var i = 0; i < spends.length; i++) {
    var bestIndex = 0;
    var bestValue = -1;

    for (var c = 0; c < cards.length; c++) {
      final result = marginalReward(
        card: cards[c],
        spend: spends[i],
        state: states[cards[c].id]!,
      );
      if (result.rupeesPaise > bestValue) {
        bestValue = result.rupeesPaise;
        bestIndex = c;
      }
    }

    assignment[i] = bestIndex;
    final chosen = cards[bestIndex];
    final applied = marginalReward(
      card: chosen,
      spend: spends[i],
      state: states[chosen.id]!,
    );
    for (final bucket in applied.buckets) {
      states[chosen.id] = states[chosen.id]!
          .withConsumption([bucket.bucketId], bucket.appliedPaise);
    }
  }

  return evaluateAllocation(
    spends: spends,
    cards: cards,
    assignment: assignment,
    initialStates: initialStates,
  );
}

/// Improve an allocation by moving single transactions between cards.
///
/// Hill-climbing from the greedy solution, to a fixed point. It escapes
/// greedy's blind spot — it *will* move a transaction onto a card that pays
/// less for that transaction alone, when doing so crosses a milestone or
/// preserves cap headroom worth more elsewhere.
///
/// It is a heuristic, and the naming says so: this is the best allocation
/// **found**, not a proven optimum. The property test pins it against
/// brute force on small instances, where the true optimum is computable.
CycleAllocation improveAllocation({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  required CycleAllocation start,
  Map<String, CycleState> initialStates = const {},
  int maxPasses = 8,
}) {
  var best = start;
  var assignment = [...start.assignment];

  for (var pass = 0; pass < maxPasses; pass++) {
    var improvedThisPass = false;

    for (var i = 0; i < spends.length; i++) {
      final original = assignment[i];
      for (var c = 0; c < cards.length; c++) {
        if (c == original) continue;
        assignment[i] = c;
        final candidate = evaluateAllocation(
          spends: spends,
          cards: cards,
          assignment: assignment,
          initialStates: initialStates,
        );
        if (candidate.totalValuePaise > best.totalValuePaise) {
          best = candidate;
          improvedThisPass = true;
        } else {
          assignment[i] = original;
        }
      }
      assignment[i] = best.assignment[i];
    }

    if (!improvedThisPass) break;
    assignment = [...best.assignment];
  }

  return best;
}

/// Allocate a cycle across cards, milestones included.
///
/// Hill-climbing alone cannot solve a milestone. Moving one transaction toward
/// a threshold *reduces* total value — you gave up a better rate and got
/// nothing yet — so every single step along the path looks like a loss and the
/// search rejects it. The reward only appears once the whole journey is made.
///
/// So the search is seeded rather than only refined. For every milestone on
/// every card, one candidate allocation is built that deliberately commits to
/// reaching that threshold, choosing the transactions that cost least to move.
/// Each seed is then hill-climbed, and the best result wins. Greedy is always
/// among the candidates, so the answer can never be worse than greedy.
///
/// This is the spec's "DP over milestone thresholds" in its practical form:
/// the milestone lattice is small — a handful of thresholds across a handful
/// of cards — so enumerating commitments is cheap, and everything between
/// thresholds is a smooth problem that local search handles well.
CycleAllocation allocateCycle({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  Map<String, CycleState> initialStates = const {},
  int maxPasses = 8,
}) {
  if (spends.isEmpty || cards.isEmpty) {
    return evaluateAllocation(
      spends: spends,
      cards: cards,
      assignment: List<int>.filled(spends.length, 0),
      initialStates: initialStates,
    );
  }

  final greedy = greedyAllocate(
    spends: spends,
    cards: cards,
    initialStates: initialStates,
  );

  var best = improveAllocation(
    spends: spends,
    cards: cards,
    start: greedy,
    initialStates: initialStates,
    maxPasses: maxPasses,
  );

  for (var c = 0; c < cards.length; c++) {
    for (final milestone in cards[c].milestones) {
      final seed = _seedTargetingMilestone(
        spends: spends,
        cards: cards,
        targetCard: c,
        thresholdPaise: milestone.thresholdPaise,
        base: greedy.assignment,
      );

      final seeded = evaluateAllocation(
        spends: spends,
        cards: cards,
        assignment: seed,
        initialStates: initialStates,
      );

      final refined = improveAllocation(
        spends: spends,
        cards: cards,
        start: seeded,
        initialStates: initialStates,
        maxPasses: maxPasses,
      );

      if (refined.totalValuePaise > best.totalValuePaise) best = refined;
    }
  }

  return best;
}

/// Build an assignment that commits to reaching [thresholdPaise] on
/// [targetCard], moving whichever transactions are cheapest to give up.
List<int> _seedTargetingMilestone({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  required int targetCard,
  required int thresholdPaise,
  required List<int> base,
}) {
  // Opportunity cost of moving a transaction onto the target: what the best
  // alternative pays, minus what the target pays. Evaluated against an empty
  // cycle, which is an approximation — it ignores how caps fill as the
  // allocation is built. That is fine here: this only has to be a good
  // starting point, and hill-climbing repairs the details afterwards.
  final ranked = <({int index, int cost, int amount})>[];
  for (var i = 0; i < spends.length; i++) {
    final onTarget = marginalReward(
      card: cards[targetCard],
      spend: spends[i],
    ).rupeesPaise;

    var bestElsewhere = 0;
    for (var c = 0; c < cards.length; c++) {
      if (c == targetCard) continue;
      final value =
          marginalReward(card: cards[c], spend: spends[i]).rupeesPaise;
      if (value > bestElsewhere) bestElsewhere = value;
    }

    ranked.add(
      (
        index: i,
        cost: bestElsewhere - onTarget,
        amount: spends[i].amountPaise,
      ),
    );
  }

  // Cheapest to move first; among equals, the largest, so the threshold is
  // reached by disturbing as few transactions as possible.
  ranked.sort((a, b) {
    final byCost = a.cost.compareTo(b.cost);
    return byCost != 0 ? byCost : b.amount.compareTo(a.amount);
  });

  final assignment = [...base];
  var running = 0;
  for (var i = 0; i < spends.length; i++) {
    if (assignment[i] == targetCard) running += spends[i].amountPaise;
  }

  for (final entry in ranked) {
    if (running >= thresholdPaise) break;
    if (assignment[entry.index] == targetCard) continue;
    assignment[entry.index] = targetCard;
    running += entry.amount;
  }

  return assignment;
}

/// Exhaustively try every assignment. Exponential — for tests only.
///
/// Exists so the heuristic can be checked against ground truth on instances
/// small enough to enumerate. Without it, "our optimizer beats greedy" is a
/// claim about two heuristics rather than a measurement.
CycleAllocation bruteForceAllocate({
  required List<SpendContext> spends,
  required List<RewardCard> cards,
  Map<String, CycleState> initialStates = const {},
  int maxSpends = 12,
}) {
  if (spends.length > maxSpends) {
    throw ArgumentError(
      'brute force refuses ${spends.length} spends; '
      '${cards.length}^${spends.length} assignments is not a test, it is a '
      'hang. Raise maxSpends deliberately if you mean it.',
    );
  }

  final assignment = List<int>.filled(spends.length, 0);
  CycleAllocation? best;

  void recurse(int index) {
    if (index == spends.length) {
      final candidate = evaluateAllocation(
        spends: spends,
        cards: cards,
        assignment: [...assignment],
        initialStates: initialStates,
      );
      if (best == null || candidate.totalValuePaise > best!.totalValuePaise) {
        best = candidate;
      }
      return;
    }
    for (var c = 0; c < cards.length; c++) {
      assignment[index] = c;
      recurse(index + 1);
    }
  }

  recurse(0);
  return best!;
}
