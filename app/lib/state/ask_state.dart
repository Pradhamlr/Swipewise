import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rewards_engine/rewards_engine.dart';
import 'package:swipewise/rules/rule_repository.dart';

/// A canned merchant so the question can be asked in one tap.
///
/// In the finished app these come from the merchant normalization cascade
/// running over an imported statement. Until that lands, these presets stand
/// in — each one exercises a different corner of the rule set: an accelerated
/// category, a channel split, a hard exclusion.
class MerchantPreset {
  const MerchantPreset({
    required this.key,
    required this.label,
    required this.channel,
    this.mcc,
    this.tags = const {},
    this.note,
  });

  final String key;
  final String label;
  final Channel channel;
  final int? mcc;
  final Set<String> tags;

  /// Shown under the answer when the outcome needs explaining.
  final String? note;
}

const merchantPresets = <MerchantPreset>[
  MerchantPreset(
    key: 'swiggy',
    label: 'Swiggy',
    channel: Channel.online,
    mcc: 5814,
    tags: {'swiggy'},
  ),
  MerchantPreset(
    key: 'amazon',
    label: 'Amazon',
    channel: Channel.online,
    mcc: 5399,
    tags: {'amazon'},
  ),
  MerchantPreset(
    key: 'utility',
    label: 'Electricity · GPay',
    channel: Channel.online,
    mcc: 4900,
    tags: {'google_pay'},
  ),
  MerchantPreset(
    key: 'grocery',
    label: 'Grocery · in store',
    channel: Channel.offline,
    mcc: 5411,
  ),
  MerchantPreset(
    key: 'fuel',
    label: 'Fuel',
    channel: Channel.offline,
    mcc: 5541,
    tags: {'fuel'},
    note: 'Excluded on every card in the bundle — the honest answer is ₹0.',
  ),
  MerchantPreset(
    key: 'rent',
    label: 'Rent',
    channel: Channel.online,
    mcc: 6513,
    tags: {'rent'},
    note: 'Rent is excluded on Axis ACE and earns base rate elsewhere.',
  ),
];

/// What the user is asking.
class AskQuery {
  const AskQuery({
    this.amountPaise = 80000,
    this.merchantKey = 'swiggy',
    this.sbiOnlineUsedPaise = 0,
    this.axisAcceleratedUsedPaise = 0,
  });

  final int amountPaise;
  final String merchantKey;

  /// Cap consumption, exposed so the demo can show the recommendation flip.
  /// In the finished app this is computed from imported transactions, not set
  /// by hand — but it is the same value flowing into the same evaluator.
  final int sbiOnlineUsedPaise;
  final int axisAcceleratedUsedPaise;

  MerchantPreset get merchant =>
      merchantPresets.firstWhere((m) => m.key == merchantKey);

  SpendContext toSpend() => SpendContext(
        amountPaise: amountPaise,
        date: DateTime.now(),
        channel: merchant.channel,
        mcc: merchant.mcc,
        tags: merchant.tags,
        merchantName: merchant.label,
      );

  Map<String, CycleState> toCycleStates() => {
        'sbi-cashback': CycleState({'online_cap': sbiOnlineUsedPaise}),
        'axis-ace': CycleState({'accelerated_cap': axisAcceleratedUsedPaise}),
      };

  AskQuery copyWith({
    int? amountPaise,
    String? merchantKey,
    int? sbiOnlineUsedPaise,
    int? axisAcceleratedUsedPaise,
  }) {
    return AskQuery(
      amountPaise: amountPaise ?? this.amountPaise,
      merchantKey: merchantKey ?? this.merchantKey,
      sbiOnlineUsedPaise: sbiOnlineUsedPaise ?? this.sbiOnlineUsedPaise,
      axisAcceleratedUsedPaise:
          axisAcceleratedUsedPaise ?? this.axisAcceleratedUsedPaise,
    );
  }
}

class AskNotifier extends Notifier<AskQuery> {
  @override
  AskQuery build() => const AskQuery();

  void setAmount(int paise) => state = state.copyWith(amountPaise: paise);

  void setMerchant(String key) => state = state.copyWith(merchantKey: key);

  void setSbiOnlineUsed(int paise) =>
      state = state.copyWith(sbiOnlineUsedPaise: paise);

  void setAxisAcceleratedUsed(int paise) =>
      state = state.copyWith(axisAcceleratedUsedPaise: paise);
}

final askProvider =
    NotifierProvider<AskNotifier, AskQuery>(AskNotifier.new);

/// The seed rule bundle. Loaded once, asynchronously, from assets.
final cardsProvider = FutureProvider<List<RewardCard>>((ref) {
  return loadBundledCards();
});

/// The answer: every card scored for the current question, best first.
///
/// A derived provider rather than something computed in the widget, so the
/// ranking is testable without a widget harness — which is the concrete reason
/// Riverpod is here rather than an inherited-widget-based solution.
final rankingProvider = Provider<CardRanking?>((ref) {
  final cards = ref.watch(cardsProvider).value;
  if (cards == null) return null;
  final query = ref.watch(askProvider);
  return rankCards(
    cards: cards,
    spend: query.toSpend(),
    states: query.toCycleStates(),
  );
});

/// The amount at which the recommendation would change.
final flipProvider = Provider<int?>((ref) {
  final cards = ref.watch(cardsProvider).value;
  if (cards == null) return null;
  final query = ref.watch(askProvider);
  return findRecommendationFlip(
    cards: cards,
    spend: query.toSpend(),
    states: query.toCycleStates(),
  );
});
