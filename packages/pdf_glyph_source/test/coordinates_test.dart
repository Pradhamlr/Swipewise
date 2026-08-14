import 'package:pdf_glyph_source/pdf_glyph_source.dart';
import 'package:test/test.dart';

void main() {
  group('toGlyphRun', () {
    // A 792pt-tall page with a glyph sitting near the bottom edge in PDF
    // terms (top=71.2, bottom=65.9) — i.e. near the *end* of the page in
    // reading order, so its flipped y should be large.
    test('flips the y axis about the page height', () {
      final run = toGlyphRun(
        text: 'g',
        pageIndex: 0,
        pageHeight: 792,
        left: 18.3,
        top: 71.2,
        right: 21.8,
        bottom: 65.9,
      );

      expect(run.x, closeTo(18.3, 1e-9));
      expect(run.y, closeTo(792 - 71.2, 1e-9));
      expect(run.width, closeTo(3.5, 1e-9));
      expect(run.height, closeTo(5.3, 1e-9));
    });

    test('a glyph at the top of the page lands at a small y', () {
      final run = toGlyphRun(
        text: 'A',
        pageIndex: 2,
        pageHeight: 792,
        left: 100,
        top: 782,
        right: 108,
        bottom: 772,
      );

      expect(run.y, closeTo(10, 1e-9));
      expect(run.bottom, closeTo(20, 1e-9));
      expect(run.centerY, closeTo(15, 1e-9));
      expect(run.pageIndex, 2);
    });

    test('reading order is monotonic in y after the flip', () {
      // Higher on the page in PDF terms (bigger top) must come first.
      final upper = toGlyphRun(
        text: 'a',
        pageIndex: 0,
        pageHeight: 600,
        left: 0,
        top: 500,
        right: 5,
        bottom: 492,
      );
      final lower = toGlyphRun(
        text: 'b',
        pageIndex: 0,
        pageHeight: 600,
        left: 0,
        top: 300,
        right: 5,
        bottom: 292,
      );

      expect(upper.y, lessThan(lower.y));
    });
  });
}
