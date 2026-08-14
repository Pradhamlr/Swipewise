import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rewards_engine/rewards_engine.dart';
import 'package:swipewise/painting/cap_gauge.dart';
import 'package:swipewise/state/ask_state.dart';
import 'package:swipewise/theme/tokens.dart';

/// Per-card cap gauges for the current cycle.
///
/// The pending arc on each gauge is what the spend currently being asked about
/// on the Ask screen would consume — so the two screens are two views of one
/// evaluation, not two separate calculations that might disagree.
class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final cards = ref.watch(cardsProvider);
    final query = ref.watch(askProvider);

    return cards.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Could not load the rule bundle: $error',
          style: TextStyle(color: tokens.danger),
        ),
      ),
      data: (loaded) {
        final states = query.toCycleStates();
        final spend = query.toSpend();

        return ListView(
          padding: const EdgeInsets.all(SwipewiseTokens.space5),
          children: [
            Text(
              'Cap state',
              style: TextStyle(
                color: tokens.textHigh,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: SwipewiseTokens.space1),
            Text(
              'Pending arc shows what a '
              '${query.merchant.label} spend would consume.',
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
            ),
            const SizedBox(height: SwipewiseTokens.space5),
            for (final card in loaded)
              _CardBlock(
                card: card,
                state: states[card.id] ?? const CycleState.empty(),
                spend: spend,
              ),
          ],
        );
      },
    );
  }
}

class _CardBlock extends StatelessWidget {
  const _CardBlock({
    required this.card,
    required this.state,
    required this.spend,
  });

  final RewardCard card;
  final CycleState state;
  final SpendContext spend;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final reward = marginalReward(card: card, spend: spend, state: state);

    // What this spend would draw from each bucket, keyed by bucket id.
    final pending = <String, int>{
      for (final outcome in reward.buckets)
        outcome.bucketId: outcome.appliedPaise,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: SwipewiseTokens.space5),
      padding: const EdgeInsets.all(SwipewiseTokens.space4),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.name,
            style: TextStyle(
              color: tokens.textHigh,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            card.issuer,
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          const SizedBox(height: SwipewiseTokens.space4),
          if (card.buckets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: SwipewiseTokens.space2),
              child: Text(
                'No caps on this card — nothing to run out of.',
                style: TextStyle(color: tokens.textMuted, fontSize: 12.5),
              ),
            )
          else
            Center(
              child: Wrap(
                spacing: SwipewiseTokens.space5,
                runSpacing: SwipewiseTokens.space5,
                alignment: WrapAlignment.center,
                children: [
                  for (final bucket in card.buckets)
                    CapGauge(
                      label: bucket.label ?? bucket.id,
                      usedPaise: state.consumedIn(bucket.id),
                      limitPaise: bucket.limitPaise,
                      pendingPaise: pending[bucket.id] ?? 0,
                      diameter: 140,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
