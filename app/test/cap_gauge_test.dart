import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipewise/format/rupees.dart';
import 'package:swipewise/painting/cap_gauge.dart';
import 'package:swipewise/theme/tokens.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: buildSwipewiseTheme(SwipewiseTokens.dark),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('formatRupees', () {
    test('groups the Indian way, not in threes', () {
      expect(formatRupees(123456789), '₹12,34,567.89');
      expect(formatRupees(1234567), '₹12,345.67');
      expect(formatRupees(100000), '₹1,000.00');
      expect(formatRupees(80000), '₹800.00');
    });

    test('handles small, zero and negative amounts', () {
      expect(formatRupees(7), '₹0.07');
      expect(formatRupees(0), '₹0.00');
      expect(formatRupees(-80000), '-₹800.00');
    });

    test('can drop the symbol and the decimals', () {
      expect(formatRupees(150000, decimals: false), '₹1,500');
      expect(formatRupees(150000, withSymbol: false), '1,500.00');
    });
  });

  group('CapGauge', () {
    testWidgets('shows how much of the cap is left', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CapGauge(
            label: 'Online cashback',
            usedPaise: 118000,
            limitPaise: 150000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the label and status line are Text widgets. The figures inside
      // the dial are drawn straight onto the canvas by TextPainter, so they
      // never enter the widget tree and find.text cannot see them — those are
      // covered by the golden test instead.
      expect(find.text('Online cashback'), findsOneWidget);
      expect(find.text('₹320 left this cycle'), findsOneWidget);
    });

    testWidgets('says a pending transaction fits', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CapGauge(
            label: 'Online cashback',
            usedPaise: 118000,
            limitPaise: 150000,
            pendingPaise: 8000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('this txn fits'), findsOneWidget);
    });

    testWidgets('warns when the transaction would breach the cap', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const CapGauge(
            label: 'Overall cashback',
            usedPaise: 196000,
            limitPaise: 200000,
            pendingPaise: 12000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1960 + 120 against a 2000 cap: 80 rupees spill past the limit.
      expect(find.text('₹80.00 over — drops to base rate'), findsOneWidget);
    });

    testWidgets('is isolated behind a RepaintBoundary', (tester) async {
      await tester.pumpWidget(
        wrap(
          const CapGauge(label: 'Dining', usedPaise: 1000, limitPaise: 5000),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(CapGauge),
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
        reason: 'without one, every gauge repaints when any gauge animates',
      );
    });
  });
}
