import 'package:rewards_engine/src/model/rules.dart';
import 'package:rewards_engine/src/model/spend.dart';

/// What one cap bucket did to a reward.
class BucketOutcome {
  const BucketOutcome({
    required this.bucketId,
    required this.label,
    required this.limitPaise,
    required this.consumedPaise,
    required this.appliedPaise,
    required this.clamped,
  });

  final String bucketId;
  final String label;
  final int limitPaise;

  /// Drawn down *before* this transaction.
  final int consumedPaise;

  /// What this transaction draws down.
  final int appliedPaise;

  /// True when this bucket is the one that limited the payout.
  final bool clamped;

  int get remainingPaise {
    final left = limitPaise - consumedPaise - appliedPaise;
    return left > 0 ? left : 0;
  }

  double get utilisation =>
      limitPaise <= 0 ? 0 : (consumedPaise + appliedPaise) / limitPaise;
}

/// The answer for one card.
class MarginalReward {
  const MarginalReward({
    required this.cardId,
    required this.rupeesPaise,
    required this.ruleId,
    required this.buckets,
    this.effectiveRate = 0,
    this.explanation,
    this.spendUntilRateDropsPaise,
  });

  const MarginalReward.none({
    required this.cardId,
    required this.explanation,
  })  : rupeesPaise = 0,
        ruleId = null,
        buckets = const [],
        effectiveRate = 0,
        spendUntilRateDropsPaise = null;

  final String cardId;

  /// Reward value in paise, already converted to rupees at the card's
  /// redemption rate. The optimizer only ever ranks in rupees — comparing a
  /// card that pays points against one that pays cashback is meaningless
  /// otherwise.
  final int rupeesPaise;

  /// Which rule fired. Null when nothing did.
  final String? ruleId;

  /// Every bucket this reward touched, for the gauges and the why panel.
  final List<BucketOutcome> buckets;

  /// Reward as a fraction of spend, after any cap clamping. This is the number
  /// to show the user — the headline "5%" is a lie once the bucket is nearly
  /// full.
  final double effectiveRate;

  /// Why this card pays what it pays, in plain English.
  final String? explanation;

  /// How much more spend of this kind before the accelerated rate stops
  /// applying. This is the "breakpoint" the answer card promises, and no
  /// comparable app shows it.
  final int? spendUntilRateDropsPaise;

  bool get isZero => rupeesPaise == 0;
}

/// Evaluate one card against one spend, given what the cycle has already
/// consumed.
///
/// Rules are tried in order. A rule that matches but whose buckets are
/// exhausted does **not** win — evaluation falls through to the next matching
/// rule, which is normally the base rate. That single behaviour is what makes
/// this an evaluator rather than a lookup table, and it is what lets the app
/// route a large spend *away* from the obvious 5% card.
MarginalReward marginalReward({
  required RewardCard card,
  required SpendContext spend,
  CycleState state = const CycleState.empty(),
}) {
  if (spend.mcc != null && card.excludedMccs.contains(spend.mcc)) {
    return MarginalReward.none(
      cardId: card.id,
      explanation: 'MCC ${spend.mcc} is excluded from rewards on this card',
    );
  }

  final excludedTag = card.excludedTags.where(spend.tags.contains).firstOrNull;
  if (excludedTag != null) {
    return MarginalReward.none(
      cardId: card.id,
      explanation: '$excludedTag spends earn nothing on this card',
    );
  }

  for (final rule in card.rules) {
    if (!predicateMatches(rule.when, spend)) continue;

    final gross = (spend.amountPaise * rule.rate).round();
    if (gross <= 0) continue;

    // The tightest bucket binds. A rule consuming both a category cap and an
    // overall cap is limited by whichever has least headroom left.
    var granted = gross;
    String? bindingBucketId;
    for (final id in rule.consumes) {
      final bucket = card.bucket(id);
      if (bucket == null) continue;
      final headroom = state.headroomIn(bucket);
      if (headroom < granted) {
        granted = headroom;
        bindingBucketId = id;
      }
    }

    // Bucket exhausted: fall through so a lower, uncapped rule can pay.
    if (granted <= 0) continue;

    final outcomes = <BucketOutcome>[
      for (final id in rule.consumes)
        if (card.bucket(id) case final bucket?)
          BucketOutcome(
            bucketId: id,
            label: bucket.label ?? id,
            limitPaise: bucket.limitPaise,
            consumedPaise: state.consumedIn(id),
            appliedPaise: granted,
            clamped: id == bindingBucketId,
          ),
    ];

    final rupees = _toRupeesPaise(granted, rule.unit, card);

    return MarginalReward(
      cardId: card.id,
      rupeesPaise: rupees,
      ruleId: rule.id,
      buckets: outcomes,
      effectiveRate: spend.amountPaise == 0 ? 0 : rupees / spend.amountPaise,
      explanation: _explain(rule, granted, gross, bindingBucketId, card),
      spendUntilRateDropsPaise: _spendUntilRateDrops(rule, card, state),
    );
  }

  return MarginalReward.none(
    cardId: card.id,
    explanation: 'no rule on this card matches this spend',
  );
}

int _toRupeesPaise(int amount, RewardUnit unit, RewardCard card) {
  return switch (unit) {
    RewardUnit.cashback => amount,
    RewardUnit.points => (amount * card.pointValuePaise / 100).round(),
  };
}

String _explain(
  RewardRule rule,
  int granted,
  int gross,
  String? bindingBucketId,
  RewardCard card,
) {
  final base = rule.description ??
      '${(rule.rate * 100).toStringAsFixed(rule.rate * 100 % 1 == 0 ? 0 : 1)}%'
          ' ${rule.unit.name}';
  if (granted < gross && bindingBucketId != null) {
    final label = card.bucket(bindingBucketId)?.label ?? bindingBucketId;
    return '$base — clipped by the $label cap';
  }
  return base;
}

/// How much further spend of this exact kind the accelerated rate survives.
int? _spendUntilRateDrops(
  RewardRule rule,
  RewardCard card,
  CycleState state,
) {
  if (rule.consumes.isEmpty || rule.rate <= 0) return null;

  var tightest = -1;
  for (final id in rule.consumes) {
    final bucket = card.bucket(id);
    if (bucket == null) continue;
    final headroom = state.headroomIn(bucket);
    if (tightest < 0 || headroom < tightest) tightest = headroom;
  }
  if (tightest < 0) return null;
  return (tightest / rule.rate).round();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
