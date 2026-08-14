import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipewise/features/answer/answer_card.dart';
import 'package:swipewise/format/rupees.dart';
import 'package:swipewise/state/ask_state.dart';
import 'package:swipewise/theme/tokens.dart';

class AskScreen extends ConsumerWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final query = ref.watch(askProvider);
    final cards = ref.watch(cardsProvider);
    final ranking = ref.watch(rankingProvider);
    final flip = ref.watch(flipProvider);

    return ListView(
      padding: const EdgeInsets.all(SwipewiseTokens.space5),
      children: [
        Text(
          'Which card?',
          style: TextStyle(
            color: tokens.textHigh,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: SwipewiseTokens.space1),
        Text(
          'Answered on device, from the issuer terms shipped with the app.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
        const SizedBox(height: SwipewiseTokens.space5),

        const _AmountField(),
        const SizedBox(height: SwipewiseTokens.space4),
        const _MerchantChips(),
        const SizedBox(height: SwipewiseTokens.space5),

        cards.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(SwipewiseTokens.space6),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text(
            'Could not load the rule bundle: $error',
            style: TextStyle(color: tokens.danger),
          ),
          data: (loaded) => ranking == null
              ? const SizedBox.shrink()
              : AnswerCard(
                  ranking: ranking,
                  cards: loaded,
                  spendPaise: query.amountPaise,
                  merchantLabel: query.merchant.label,
                  mcc: query.merchant.mcc,
                  flipPaise: flip,
                  note: query.merchant.note,
                ),
        ),

        const SizedBox(height: SwipewiseTokens.space6),
        const _CycleControls(),
      ],
    );
  }
}

class _AmountField extends ConsumerStatefulWidget {
  const _AmountField();

  @override
  ConsumerState<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends ConsumerState<_AmountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final paise = ref.read(askProvider).amountPaise;
    _controller = TextEditingController(text: (paise ~/ 100).toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String raw) {
    final rupees = int.tryParse(raw.replaceAll(RegExp('[^0-9]'), ''));
    if (rupees == null) return;
    ref.read(askProvider.notifier).setAmount(rupees * 100);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _apply,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            color: tokens.textHigh,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle: TextStyle(
              color: tokens.textMuted,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: tokens.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
              borderSide: BorderSide(color: tokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
              borderSide: BorderSide(color: tokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
              borderSide: BorderSide(color: tokens.accent),
            ),
          ),
        ),
        const SizedBox(height: SwipewiseTokens.space2),
        Wrap(
          spacing: SwipewiseTokens.space2,
          children: [
            for (final amount in [500, 800, 2000, 20000])
              ActionChip(
                label: Text(formatRupees(amount * 100, decimals: false)),
                onPressed: () {
                  _controller.text = amount.toString();
                  ref.read(askProvider.notifier).setAmount(amount * 100);
                },
                backgroundColor: tokens.surface,
                side: BorderSide(color: tokens.border),
                labelStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
          ],
        ),
      ],
    );
  }
}

class _MerchantChips extends ConsumerWidget {
  const _MerchantChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final selected = ref.watch(askProvider).merchantKey;

    return Wrap(
      spacing: SwipewiseTokens.space2,
      runSpacing: SwipewiseTokens.space2,
      children: [
        for (final preset in merchantPresets)
          ChoiceChip(
            label: Text(preset.label),
            selected: preset.key == selected,
            onSelected: (_) =>
                ref.read(askProvider.notifier).setMerchant(preset.key),
            backgroundColor: tokens.surface,
            selectedColor: tokens.accent.withValues(alpha: 0.18),
            side: BorderSide(
              color: preset.key == selected ? tokens.accent : tokens.border,
            ),
            labelStyle: TextStyle(
              color: preset.key == selected ? tokens.accent : tokens.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            showCheckmark: false,
          ),
      ],
    );
  }
}

/// Cap consumption controls.
///
/// In the finished app these values come from the imported statement. Exposing
/// them as sliders here is what makes the central claim visible in one screen:
/// drag the SBI cap toward full and watch the recommendation change without
/// any headline rate changing.
class _CycleControls extends ConsumerWidget {
  const _CycleControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final query = ref.watch(askProvider);

    return Container(
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
            'Cycle so far',
            style: TextStyle(
              color: tokens.textHigh,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Normally read from your statement. Drag it and the answer above '
            'changes — no headline rate moved.',
            style: TextStyle(color: tokens.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: SwipewiseTokens.space3),
          _CapSlider(
            label: 'SBI online cashback used',
            valuePaise: query.sbiOnlineUsedPaise,
            maxPaise: 200000,
            onChanged: ref.read(askProvider.notifier).setSbiOnlineUsed,
          ),
          _CapSlider(
            label: 'Axis accelerated cashback used',
            valuePaise: query.axisAcceleratedUsedPaise,
            maxPaise: 50000,
            onChanged: ref.read(askProvider.notifier).setAxisAcceleratedUsed,
          ),
        ],
      ),
    );
  }
}

class _CapSlider extends StatelessWidget {
  const _CapSlider({
    required this.label,
    required this.valuePaise,
    required this.maxPaise,
    required this.onChanged,
  });

  final String label;
  final int valuePaise;
  final int maxPaise;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ),
            Text(
              '${formatRupees(valuePaise, decimals: false)} / '
              '${formatRupees(maxPaise, decimals: false)}',
              style: TextStyle(
                color: tokens.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: valuePaise.toDouble().clamp(0, maxPaise.toDouble()),
          max: maxPaise.toDouble(),
          activeColor: tokens.accent,
          inactiveColor: tokens.border,
          onChanged: (value) => onChanged(value.round()),
        ),
      ],
    );
  }
}
