import 'package:rewards_engine/src/evaluator.dart';
import 'package:rewards_engine/src/model/rules.dart';
import 'package:rewards_engine/src/model/spend.dart';

/// Every card scored for one spend, best first.
class CardRanking {
  const CardRanking(this.ranked);

  /// Sorted by reward value descending. Ties keep their input order, so a
  /// deterministic card list gives a deterministic answer.
  final List<MarginalReward> ranked;

  MarginalReward? get winner => ranked.isEmpty ? null : ranked.first;

  MarginalReward? get runnerUp => ranked.length < 2 ? null : ranked[1];

  /// What choosing the winner is worth over the next-best card. This is the
  /// number that makes the recommendation feel earned rather than asserted.
  int get advantagePaise {
    final best = winner;
    final second = runnerUp;
    if (best == null || second == null) return 0;
    return best.rupeesPaise - second.rupeesPaise;
  }
}

/// Score every card for one spend and rank them in rupees.
///
/// Problem A from the spec — argmax over the evaluator. Genuinely trivial, and
/// worth saying so: the hard problem is cycle *allocation*, where milestones
/// make greedy per-transaction routing provably suboptimal.
CardRanking rankCards({
  required List<RewardCard> cards,
  required SpendContext spend,
  Map<String, CycleState> states = const {},
}) {
  final scored = [
    for (final card in cards)
      marginalReward(
        card: card,
        spend: spend,
        state: states[card.id] ?? const CycleState.empty(),
      ),
  ]..sort((a, b) => b.rupeesPaise.compareTo(a.rupeesPaise));

  return CardRanking(scored);
}

/// The smallest spend above [spend]'s amount at which the winning card
/// changes, or null if it never does within [maxPaise].
///
/// This is the "breakpoint" — the third thing the answer card shows that no
/// comparable app does. It exists because caps make the best card a function
/// of *how much* you are about to spend: a 5% card with ₹200 of headroom left
/// beats a flat 1.5% card on ₹1,000 and loses on ₹50,000.
int? findRecommendationFlip({
  required List<RewardCard> cards,
  required SpendContext spend,
  Map<String, CycleState> states = const {},
  int maxPaise = 50000000, // ₹5,00,000
}) {
  String? winnerAt(int amountPaise) {
    final ranking = rankCards(
      cards: cards,
      spend: SpendContext(
        amountPaise: amountPaise,
        date: spend.date,
        channel: spend.channel,
        mcc: spend.mcc,
        tags: spend.tags,
        merchantName: spend.merchantName,
      ),
      states: states,
    );
    final best = ranking.winner;
    if (best == null || best.isZero) return null;
    return best.cardId;
  }

  final current = winnerAt(spend.amountPaise);
  if (current == null) return null;

  // Expand until the answer changes, then bisect for the exact rupee.
  var low = spend.amountPaise;
  var high = low * 2 + 100;
  while (high <= maxPaise && winnerAt(high) == current) {
    low = high;
    high *= 2;
  }
  if (high > maxPaise) return null;

  while (low + 100 < high) {
    final mid = low + (high - low) ~/ 2;
    if (winnerAt(mid) == current) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return high;
}
