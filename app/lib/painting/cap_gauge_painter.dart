import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:swipewise/format/rupees.dart';

/// Paints a cap bucket as a 270° arc gauge.
///
/// Hand-written rather than pulled from a charting library, deliberately: the
/// gauge has to show three quantities at once — what is already consumed, what
/// *this* transaction would consume, and where the limit is — and no chart
/// library models "pending" as a first-class thing. Drawing it directly is
/// both less code than bending a library into shape and the honest way to show
/// the one number that matters: whether this spend still fits.
class CapGaugePainter extends CustomPainter {
  const CapGaugePainter({
    required this.usedFraction,
    required this.pendingFraction,
    required this.progress,
    required this.trackColor,
    required this.usedColor,
    required this.pendingColor,
    required this.overflowColor,
    required this.centreLabel,
    required this.subLabel,
    required this.textHigh,
    required this.textMuted,
  });

  /// Fraction of the bucket already consumed this cycle, 0..1+.
  final double usedFraction;

  /// Fraction this transaction would additionally consume.
  final double pendingFraction;

  /// Animation progress, 0..1. Sweeps the arcs in on first paint.
  final double progress;

  final Color trackColor;
  final Color usedColor;
  final Color pendingColor;
  final Color overflowColor;

  final String centreLabel;
  final String subLabel;
  final Color textHigh;
  final Color textMuted;

  static const _startAngle = math.pi * 0.75; // 135°, bottom-left
  static const _sweepAngle = math.pi * 1.5; // 270°, gap at the bottom

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.085;
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(stroke / 2 + size.shortestSide * 0.06);
    final centre = rect.center;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    canvas.drawArc(rect, _startAngle, _sweepAngle, false, track);

    _paintTicks(canvas, centre, rect, stroke);

    // Clamp so an over-consumed bucket does not wrap past the track; the
    // overflow is communicated by colour instead.
    final used = (usedFraction * progress).clamp(0.0, 1.0);
    final pendingStart = used;
    final pendingEnd = ((usedFraction + pendingFraction) * progress).clamp(
      0.0,
      1.0,
    );
    final overflows = usedFraction + pendingFraction > 1.0;

    if (pendingEnd > pendingStart) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = overflows ? overflowColor : pendingColor;
      canvas.drawArc(
        rect,
        _startAngle + _sweepAngle * pendingStart,
        _sweepAngle * (pendingEnd - pendingStart),
        false,
        paint,
      );
    }

    if (used > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: [usedColor.withValues(alpha: 0.55), usedColor],
          transform: GradientRotation(_startAngle),
        ).createShader(rect);
      canvas.drawArc(rect, _startAngle, _sweepAngle * used, false, paint);
    }

    _paintText(canvas, size);
  }

  void _paintTicks(Canvas canvas, Offset centre, Rect rect, double stroke) {
    final paint = Paint()
      ..color = trackColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final outer = rect.width / 2 + stroke * 0.85;
    final inner = rect.width / 2 + stroke * 0.45;

    for (var i = 0; i <= 4; i++) {
      final angle = _startAngle + _sweepAngle * (i / 4);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + direction * inner,
        centre + direction * outer,
        paint,
      );
    }
  }

  void _paintText(Canvas canvas, Size size) {
    final centre = TextPainter(
      text: TextSpan(
        text: centreLabel,
        style: TextStyle(
          color: textHigh,
          fontSize: size.shortestSide * 0.155,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.7);

    final sub = TextPainter(
      text: TextSpan(
        text: subLabel,
        style: TextStyle(
          color: textMuted,
          fontSize: size.shortestSide * 0.075,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.8);

    final block = centre.height + sub.height + 2;
    final top = (size.height - block) / 2;

    centre.paint(canvas, Offset((size.width - centre.width) / 2, top));
    sub.paint(
      canvas,
      Offset((size.width - sub.width) / 2, top + centre.height + 2),
    );
  }

  @override
  bool shouldRepaint(CapGaugePainter old) {
    return old.usedFraction != usedFraction ||
        old.pendingFraction != pendingFraction ||
        old.progress != progress ||
        old.centreLabel != centreLabel ||
        old.subLabel != subLabel ||
        old.usedColor != usedColor ||
        old.pendingColor != pendingColor;
  }
}

/// Convenience for building the gauge's centre label from paise.
String gaugeCentreLabel(int usedPaise) =>
    formatRupees(usedPaise, decimals: false);
