import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipewise/painting/cap_gauge.dart';
import 'package:swipewise/theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: SwipewiseApp()));
}

class SwipewiseApp extends StatelessWidget {
  const SwipewiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swipewise',
      debugShowCheckedModeBanner: false,
      theme: buildSwipewiseTheme(SwipewiseTokens.dark),
      home: const CapGaugeGallery(),
    );
  }
}

/// Temporary scaffold so the painting work is visible while the evaluator is
/// being built. Replaced by the Cards screen once real cap state exists.
class CapGaugeGallery extends StatefulWidget {
  const CapGaugeGallery({super.key});

  @override
  State<CapGaugeGallery> createState() => _CapGaugeGalleryState();
}

class _CapGaugeGalleryState extends State<CapGaugeGallery> {
  bool _showPending = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SwipewiseTokens.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cap state',
                style: TextStyle(
                  color: tokens.textHigh,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: SwipewiseTokens.space1),
              Text(
                'This cycle · resets in 12 days',
                style: TextStyle(color: tokens.textMuted, fontSize: 13),
              ),
              const SizedBox(height: SwipewiseTokens.space6),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: SwipewiseTokens.space5,
                    runSpacing: SwipewiseTokens.space6,
                    alignment: WrapAlignment.center,
                    children: [
                      CapGauge(
                        label: 'Online cashback',
                        usedPaise: 118000,
                        limitPaise: 150000,
                        pendingPaise: _showPending ? 8000 : 0,
                      ),
                      CapGauge(
                        label: 'Dining accelerated',
                        usedPaise: 42000,
                        limitPaise: 100000,
                        pendingPaise: _showPending ? 4000 : 0,
                      ),
                      CapGauge(
                        label: 'Overall cashback',
                        usedPaise: 196000,
                        limitPaise: 200000,
                        pendingPaise: _showPending ? 12000 : 0,
                      ),
                      const CapGauge(
                        label: 'Fuel surcharge waiver',
                        usedPaise: 25000,
                        limitPaise: 25000,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SwipewiseTokens.space4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      setState(() => _showPending = !_showPending),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.surfaceRaised,
                    foregroundColor: tokens.textHigh,
                    padding: const EdgeInsets.symmetric(
                      vertical: SwipewiseTokens.space4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(SwipewiseTokens.radius),
                    ),
                  ),
                  child: Text(
                    _showPending
                        ? 'Hide pending transaction'
                        : 'Preview a ₹800 dining spend',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
