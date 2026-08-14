import 'package:flutter/material.dart';
import 'package:swipewise/format/rupees.dart';
import 'package:swipewise/painting/cap_gauge_painter.dart';
import 'package:swipewise/theme/tokens.dart';

/// A cap bucket rendered as an animated arc gauge.
///
/// Wrapped in a [RepaintBoundary] on purpose. Without one, the gauge's
/// animation dirties its whole ancestor chain and every sibling repaints on
/// each frame — on the Cards screen that means four gauges each forcing the
/// other three to redraw. The boundary gives this subtree its own layer so the
/// raster work stays proportional to what actually changed.
class CapGauge extends StatelessWidget {
  const CapGauge({
    required this.label,
    required this.usedPaise,
    required this.limitPaise,
    this.pendingPaise = 0,
    this.diameter = 168,
    super.key,
  });

  /// Name of the bucket, e.g. "Online cashback".
  final String label;

  /// Consumed so far this cycle.
  final int usedPaise;

  /// The bucket's limit.
  final int limitPaise;

  /// What the transaction under consideration would additionally consume.
  final int pendingPaise;

  final double diameter;

  double get _usedFraction => limitPaise <= 0 ? 0 : usedPaise / limitPaise;

  double get _pendingFraction =>
      limitPaise <= 0 ? 0 : pendingPaise / limitPaise;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final utilisation = _usedFraction + _pendingFraction;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) {
              return CustomPaint(
                size: Size.square(diameter),
                isComplex: true,
                painter: CapGaugePainter(
                  usedFraction: _usedFraction,
                  pendingFraction: _pendingFraction,
                  progress: progress,
                  trackColor: tokens.border,
                  usedColor: tokens.forUtilisation(_usedFraction),
                  pendingColor: tokens.warning,
                  overflowColor: tokens.danger,
                  centreLabel: gaugeCentreLabel(usedPaise),
                  subLabel: 'of ${formatRupees(limitPaise, decimals: false)}',
                  textHigh: tokens.textHigh,
                  textMuted: tokens.textMuted,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: SwipewiseTokens.space2),
        Text(
          label,
          style: TextStyle(
            color: tokens.textHigh,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _statusLine(utilisation),
          style: TextStyle(
            color: tokens.forUtilisation(utilisation),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _statusLine(double utilisation) {
    if (limitPaise <= 0) return 'no cap';
    if (utilisation > 1) {
      final over = usedPaise + pendingPaise - limitPaise;
      return '${formatRupees(over)} over — drops to base rate';
    }
    if (pendingPaise > 0) return 'this txn fits';
    final left = limitPaise - usedPaise;
    return '${formatRupees(left, decimals: false)} left this cycle';
  }
}
