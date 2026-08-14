/// How a purchase was made. Reward rules routinely split on this.
enum Channel { online, offline }

/// What a rule pays out in. Points are converted to rupees at the card's
/// declared redemption value, never baked into the rule — the same point is
/// worth different amounts through statement credit, airmiles or a catalogue.
enum RewardUnit { cashback, points }

/// How often a cap bucket refills.
enum CapPeriod { cycle, month, year }

/// The closed predicate grammar.
///
/// Nine operators, and adding a tenth is a deliberate act that bumps the
/// schema version. An unbounded language — JSONLogic, CEL — would be
/// untestable and impossible for a contributor to write correctly, and there
/// would be no way to prove the evaluator handles every case. Being `sealed`
/// means the evaluator's switch is checked for exhaustiveness at compile time:
/// add an operator without handling it and the build fails.
sealed class Predicate {
  const Predicate();
}

/// Always fires. The base-rate rule's condition.
class Always extends Predicate {
  const Always();
}

class AllOf extends Predicate {
  const AllOf(this.terms);
  final List<Predicate> terms;
}

class AnyOf extends Predicate {
  const AnyOf(this.terms);
  final List<Predicate> terms;
}

class NotPredicate extends Predicate {
  const NotPredicate(this.term);
  final Predicate term;
}

class MccIn extends Predicate {
  const MccIn(this.codes);
  final Set<int> codes;
}

class ChannelIs extends Predicate {
  const ChannelIs(this.channel);
  final Channel channel;
}

/// Matches on merchant *tags* — `rent`, `wallet_load`, `fuel` — rather than
/// merchant names, because exclusions in T&Cs are written by category.
class MerchantIn extends Predicate {
  const MerchantIn(this.tags);
  final Set<String> tags;
}

class AmountAtLeast extends Predicate {
  const AmountAtLeast(this.paise);
  final int paise;
}

class DateBetween extends Predicate {
  const DateBetween({required this.from, required this.to});
  final DateTime from;
  final DateTime to;
}

/// A named, first-class cap.
///
/// **This is the central design decision of the engine.** The obvious schema
/// puts a cap on the rule that earns it. Real Indian cards break that
/// immediately: a single ₹1,500 monthly cashback ceiling is shared across
/// several accelerated categories, and a per-category cap often sits *inside*
/// that overall ceiling. Modelling caps as named buckets that rules reference
/// makes both fall out for free — a rule simply consumes more than one bucket,
/// and the tightest one binds.
class CapBucket {
  const CapBucket({
    required this.id,
    required this.limitPaise,
    required this.unit,
    this.period = CapPeriod.cycle,
    this.label,
  });

  final String id;

  /// The ceiling, expressed in [unit] — paise of cashback, or points × 100.
  final int limitPaise;

  final RewardUnit unit;
  final CapPeriod period;

  /// Human label for the gauge on the Cards screen.
  final String? label;
}

/// One earn rule.
class RewardRule {
  const RewardRule({
    required this.id,
    required this.when,
    required this.rate,
    required this.unit,
    this.consumes = const [],
    this.description,
  });

  final String id;
  final Predicate when;

  /// Fraction of the spend earned, e.g. 0.05 for 5%.
  final double rate;

  final RewardUnit unit;

  /// Ids of the [CapBucket]s this rule draws down. The tightest binds.
  final List<String> consumes;

  /// Plain-English summary, shown in the why panel.
  final String? description;
}

/// A card as the evaluator sees it: buckets, ordered rules, exclusions, and
/// the provenance that makes any of it believable.
class RewardCard {
  const RewardCard({
    required this.id,
    required this.name,
    required this.issuer,
    required this.rules,
    required this.sourceUrl,
    required this.retrievedOn,
    required this.validFrom,
    this.buckets = const [],
    this.excludedMccs = const {},
    this.excludedTags = const {},
    this.pointValuePaise = 0,
  });

  final String id;
  final String name;
  final String issuer;

  final List<CapBucket> buckets;

  /// Evaluated in order; the first rule that matches *and* has cap headroom
  /// wins. Put accelerated rules before the base rate.
  final List<RewardRule> rules;

  /// Spend categories that earn nothing at all on this card.
  final Set<int> excludedMccs;
  final Set<String> excludedTags;

  /// Rupee value of one point, in paise. Zero for pure cashback cards.
  final int pointValuePaise;

  /// Where these terms came from, and when. A card without these does not go
  /// in the bundle — every rate here has to be traceable to the issuer.
  final String sourceUrl;
  final DateTime retrievedOn;
  final DateTime validFrom;

  CapBucket? bucket(String id) {
    for (final bucket in buckets) {
      if (bucket.id == id) return bucket;
    }
    return null;
  }
}
