import 'package:flutter/material.dart';
import 'package:rewards_engine/rewards_engine.dart';
import 'package:swipewise/format/rupees.dart';
import 'package:swipewise/theme/tokens.dart';

/// The answer to "which card do I use, and what do I get?".
///
/// Three things here that comparable apps do not show, and all three are the
/// point of the app rather than decoration:
///
/// * the **runner-up in rupees**, never in points — a card paying 4 points is
///   incomparable to one paying 2% until both are in the same unit;
/// * the **live cap state**, because a headline 5% is a lie once its bucket is
///   nearly full;
/// * the **breakpoint** — the amount at which this recommendation flips.
class AnswerCard extends StatefulWidget {
  const AnswerCard({
    required this.ranking,
    required this.cards,
    required this.spendPaise,
    required this.merchantLabel,
    required this.mcc,
    this.flipPaise,
    this.note,
    super.key,
  });

  final CardRanking ranking;
  final List<RewardCard> cards;
  final int spendPaise;
  final String merchantLabel;
  final int? mcc;
  final int? flipPaise;
  final String? note;

  @override
  State<AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<AnswerCard> {
  bool _showWhy = false;

  RewardCard _cardFor(String id) =>
      widget.cards.firstWhere((card) => card.id == id);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final winner = widget.ranking.winner;
    final runnerUp = widget.ranking.runnerUp;

    if (winner == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SwipewiseTokens.space5),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(tokens),
          const SizedBox(height: SwipewiseTokens.space4),
          if (winner.isZero)
            _noReward(tokens, winner)
          else ...[
            _winner(tokens, winner),
            if (runnerUp != null && !runnerUp.isZero) ...[
              const SizedBox(height: SwipewiseTokens.space2),
              _runnerUp(tokens, runnerUp),
            ],
            const SizedBox(height: SwipewiseTokens.space4),
            ..._capLines(tokens, winner),
          ],
          if (widget.note != null) ...[
            const SizedBox(height: SwipewiseTokens.space3),
            Text(
              widget.note!,
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: SwipewiseTokens.space3),
          _whyToggle(tokens),
          if (_showWhy) ...[
            const SizedBox(height: SwipewiseTokens.space3),
            _whyPanel(tokens, winner),
          ],
        ],
      ),
    );
  }

  Widget _header(SwipewiseTokens tokens) {
    final parts = [
      widget.merchantLabel,
      formatRupees(widget.spendPaise, decimals: false),
      if (widget.mcc != null) 'MCC ${widget.mcc}',
    ];
    return Text(
      parts.join('  ·  '),
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _noReward(SwipewiseTokens tokens, MarginalReward winner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No card earns on this',
          style: TextStyle(
            color: tokens.textHigh,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SwipewiseTokens.space1),
        Text(
          'Use whichever card costs least to carry — the reward is ₹0 either '
          'way.',
          style: TextStyle(color: tokens.textMuted, fontSize: 13),
        ),
      ],
    );
  }

  Widget _winner(SwipewiseTokens tokens, MarginalReward winner) {
    final card = _cardFor(winner.cardId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use ${card.name}',
                style: TextStyle(
                  color: tokens.textHigh,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                card.issuer,
                style: TextStyle(color: tokens.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatRupees(winner.rupeesPaise),
              style: TextStyle(
                color: tokens.accent,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            Text(
              '${(winner.effectiveRate * 100).toStringAsFixed(2)}% back',
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _runnerUp(SwipewiseTokens tokens, MarginalReward runnerUp) {
    final card = _cardFor(runnerUp.cardId);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Runner-up: ${card.name}',
            style: TextStyle(color: tokens.textMuted, fontSize: 13),
          ),
        ),
        Text(
          '${formatRupees(runnerUp.rupeesPaise)}  '
          '(${(runnerUp.effectiveRate * 100).toStringAsFixed(2)}%)',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<Widget> _capLines(SwipewiseTokens tokens, MarginalReward winner) {
    final lines = <Widget>[];

    for (final bucket in winner.buckets) {
      final tight = bucket.clamped || bucket.utilisation >= 0.8;
      lines.add(
        _infoLine(
          tokens,
          icon: tight ? Icons.warning_amber_rounded : Icons.check_circle,
          color: tight ? tokens.warning : tokens.accent,
          text:
              '${bucket.label}: '
              '${formatRupees(bucket.consumedPaise + bucket.appliedPaise, decimals: false)} '
              'of ${formatRupees(bucket.limitPaise, decimals: false)} used'
              '${bucket.clamped ? " — this txn is clipped" : " · this txn fits"}',
        ),
      );
    }

    final untilDrop = winner.spendUntilRateDropsPaise;
    if (untilDrop != null && untilDrop > 0) {
      lines.add(
        _infoLine(
          tokens,
          icon: Icons.trending_down_rounded,
          color: tokens.textMuted,
          text:
              'Next ${formatRupees(untilDrop, decimals: false)} of this kind '
              'drops you to the base rate.',
        ),
      );
    }

    if (widget.flipPaise != null) {
      lines.add(
        _infoLine(
          tokens,
          icon: Icons.swap_horiz_rounded,
          color: tokens.textMuted,
          text:
              'Above ${formatRupees(widget.flipPaise!, decimals: false)}, '
              'a different card wins.',
        ),
      );
    }

    return lines;
  }

  Widget _infoLine(
    SwipewiseTokens tokens, {
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SwipewiseTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: SwipewiseTokens.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: tokens.textHigh.withValues(alpha: 0.85),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whyToggle(SwipewiseTokens tokens) {
    return GestureDetector(
      onTap: () => setState(() => _showWhy = !_showWhy),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Text(
            _showWhy ? 'Hide the reasoning' : 'Why this card?',
            style: TextStyle(
              color: tokens.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(
            _showWhy ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: tokens.accent,
          ),
        ],
      ),
    );
  }

  /// The trust layer: which rule fired, where its terms came from, and why
  /// every other card lost.
  Widget _whyPanel(SwipewiseTokens tokens, MarginalReward winner) {
    final card = _cardFor(winner.cardId);
    return Container(
      padding: const EdgeInsets.all(SwipewiseTokens.space4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(SwipewiseTokens.radius - 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _whyRow(tokens, 'Rule', winner.ruleId ?? '—'),
          _whyRow(tokens, 'Terms', winner.explanation ?? '—'),
          _whyRow(
            tokens,
            'Source',
            '${Uri.parse(card.sourceUrl).host} · retrieved '
                '${_date(card.retrievedOn)}',
          ),
          _whyRow(tokens, 'In force from', _date(card.validFrom)),
          const SizedBox(height: SwipewiseTokens.space3),
          Text(
            'Why the others lost',
            style: TextStyle(
              color: tokens.textHigh,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: SwipewiseTokens.space2),
          for (final loser in widget.ranking.ranked.skip(1))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_cardFor(loser.cardId).name} — '
                '${formatRupees(loser.rupeesPaise)} · '
                '${loser.explanation ?? "no matching rule"}',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _whyRow(SwipewiseTokens tokens, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: tokens.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}
