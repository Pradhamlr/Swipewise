import 'package:rewards_engine/src/model/rules.dart';

/// A purchase being evaluated — real or hypothetical.
class SpendContext {
  const SpendContext({
    required this.amountPaise,
    required this.date,
    this.channel = Channel.online,
    this.mcc,
    this.tags = const {},
    this.merchantName,
  });

  /// Always positive here. The engine reasons about spends; the sign
  /// convention for debits belongs to the statement side.
  final int amountPaise;

  final DateTime date;
  final Channel channel;

  /// Merchant category code. Null when normalization could not infer one, in
  /// which case MCC-based rules simply do not fire — silently guessing an MCC
  /// would inflate the reward the user is promised.
  final int? mcc;

  /// Category tags such as `rent`, `fuel`, `wallet_load`, `utility`.
  final Set<String> tags;

  final String? merchantName;
}

/// How much of each cap bucket has been consumed in the current cycle.
///
/// The evaluator is stateful with respect to this, which is the whole
/// difference between a real evaluator and a lookup table: the same ₹800 at
/// Swiggy is worth 5% early in the cycle and 1% once the bucket is spent.
class CycleState {
  const CycleState(this.consumed);

  const CycleState.empty() : consumed = const {};

  /// Bucket id → amount already drawn down, in that bucket's unit.
  final Map<String, int> consumed;

  int consumedIn(String bucketId) => consumed[bucketId] ?? 0;

  int headroomIn(CapBucket bucket) {
    final remaining = bucket.limitPaise - consumedIn(bucket.id);
    return remaining > 0 ? remaining : 0;
  }

  /// A new state with [amount] added to each of [bucketIds].
  CycleState withConsumption(Iterable<String> bucketIds, int amount) {
    final next = Map<String, int>.from(consumed);
    for (final id in bucketIds) {
      next[id] = (next[id] ?? 0) + amount;
    }
    return CycleState(next);
  }
}

/// Does [predicate] hold for [spend]?
///
/// The switch is exhaustive over the sealed [Predicate] hierarchy, so adding
/// an operator to the grammar without teaching the evaluator about it is a
/// compile error rather than a rule that silently never fires.
bool predicateMatches(Predicate predicate, SpendContext spend) {
  return switch (predicate) {
    Always() => true,
    AllOf(:final terms) => terms.every((term) => predicateMatches(term, spend)),
    AnyOf(:final terms) => terms.any((term) => predicateMatches(term, spend)),
    NotPredicate(:final term) => !predicateMatches(term, spend),
    MccIn(:final codes) => spend.mcc != null && codes.contains(spend.mcc),
    ChannelIs(:final channel) => spend.channel == channel,
    MerchantIn(:final tags) => tags.any(spend.tags.contains),
    AmountAtLeast(:final paise) => spend.amountPaise >= paise,
    DateBetween(:final from, :final to) =>
      !spend.date.isBefore(from) && !spend.date.isAfter(to),
  };
}
