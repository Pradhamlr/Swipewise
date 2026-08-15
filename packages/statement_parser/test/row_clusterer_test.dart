import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

/// Build a glyph as if it were typeset at [size] points with its centre on
/// [centerY], which is how real glyphs of different sizes share a line.
GlyphRun glyph(
  String text, {
  required double x,
  required double centerY,
  double size = 8,
  double width = 4,
  int page = 0,
}) {
  return GlyphRun(
    text: text,
    pageIndex: page,
    x: x,
    y: centerY - size / 2,
    width: width,
    height: size,
  );
}

/// A glyph sitting *on* a baseline, which is how type actually works — the
/// ink box grows upward from the baseline, so a short glyph and a tall one on
/// the same line share a bottom edge, not a centre.
GlyphRun onBaseline(
  String text, {
  required double x,
  required double baseline,
  double size = 8,
  double width = 4,
  int page = 0,
}) {
  return GlyphRun(
    text: text,
    pageIndex: page,
    x: x,
    y: baseline - size,
    width: width,
    height: size,
  );
}

/// A run of glyphs laid out left to right on one baseline.
List<GlyphRun> line(
  String text, {
  required double centerY,
  double startX = 0,
  double size = 8,
  double advance = 5,
  int page = 0,
}) {
  final runs = <GlyphRun>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] == ' ') continue;
    runs.add(
      glyph(
        text[i],
        x: startX + i * advance,
        centerY: centerY,
        size: size,
        page: page,
      ),
    );
  }
  return runs;
}

void main() {
  const clusterer = RowClusterer();

  group('RowClusterer', () {
    test('an empty input yields no rows', () {
      expect(clusterer.cluster([]), isEmpty);
    });

    test('glyphs on one baseline form one row', () {
      final rows = clusterer.cluster(line('SWIGGY', centerY: 100));
      expect(rows, hasLength(1));
      expect(rows.single.glyphs, hasLength(6));
    });

    test('separated baselines form separate rows, top to bottom', () {
      final rows = clusterer.cluster([
        ...line('SECOND', centerY: 130),
        ...line('FIRST', centerY: 100),
      ]);

      expect(rows, hasLength(2));
      expect(rows.first.centerY, lessThan(rows.last.centerY));
      expect(rows.first.text, 'FIRST');
      expect(rows.last.text, 'SECOND');
    });

    test('mixed font sizes on one line stay together', () {
      // The reason clustering keys on centerY rather than y: a 12pt amount
      // and a 7pt descriptor on the same printed line have tops 2.5pt apart
      // but centres that coincide.
      final rows = clusterer.cluster([
        ...line('DESC', centerY: 200, size: 7),
        ...line('1234', centerY: 200, startX: 300, size: 12),
      ]);

      expect(rows, hasLength(1), reason: 'one printed line, two font sizes');
      expect(rows.single.glyphs, hasLength(8));
    });

    test('a slightly drifting baseline does not shed its right-hand end', () {
      // Real baselines are not perfectly flat after coordinate conversion.
      final drifting = <GlyphRun>[];
      for (var i = 0; i < 40; i++) {
        drifting.add(glyph('X', x: i * 5, centerY: 100 + i * 0.05));
      }
      final rows = clusterer.cluster(drifting);
      expect(rows, hasLength(1));
      expect(rows.single.glyphs, hasLength(40));
    });

    test('a decimal point stays on the line it belongs to', () {
      // Regression, and the reason clustering keys on the baseline. A full
      // stop inks a box a fifth the height of a digit; on a real statement
      // this split "1443.98" into "144398" on one row and "." on another,
      // which the running-balance check then caught as a mismatch.
      final amount = <GlyphRun>[
        onBaseline('1', x: 0, baseline: 100),
        onBaseline('4', x: 5, baseline: 100),
        onBaseline('4', x: 10, baseline: 100),
        onBaseline('3', x: 15, baseline: 100),
        onBaseline('.', x: 20, baseline: 100, size: 1.6, width: 1.5),
        onBaseline('9', x: 23, baseline: 100),
        onBaseline('8', x: 28, baseline: 100),
      ];

      final rows = clusterer.cluster(amount);
      expect(rows, hasLength(1), reason: 'one printed number, one row');
      expect(rows.single.text, '1443.98');
    });

    test('a tall and a short glyph on one baseline stay together', () {
      final rows = clusterer.cluster([
        onBaseline('A', x: 0, baseline: 50, size: 12),
        onBaseline(',', x: 6, baseline: 50, size: 2, width: 1.5),
        onBaseline('B', x: 10, baseline: 50, size: 12),
      ]);
      expect(rows, hasLength(1));
    });

    test('glyphs come back in reading order regardless of input order', () {
      // Adjacent (each glyph is 4 wide), so no word gap is inferred and the
      // assertion is purely about ordering.
      final rows = clusterer.cluster([
        glyph('C', x: 18, centerY: 50),
        glyph('A', x: 10, centerY: 50),
        glyph('B', x: 14, centerY: 50),
      ]);
      expect(rows.single.text, 'ABC');
    });

    test('pages are kept apart even at identical y', () {
      final rows = clusterer.cluster([
        ...line('PAGEONE', centerY: 100),
        ...line('PAGETWO', centerY: 100, page: 1),
      ]);

      expect(rows, hasLength(2));
      expect(rows.first.pageIndex, 0);
      expect(rows.last.pageIndex, 1);
    });

    test('tolerance is relative to glyph height, not absolute points', () {
      // The same layout typeset twice as large must cluster identically.
      final small = clusterer.cluster([
        ...line('AB', centerY: 100, size: 6),
        ...line('CD', centerY: 108, size: 6),
      ]);
      final large = clusterer.cluster([
        ...line('AB', centerY: 200, size: 12),
        ...line('CD', centerY: 216, size: 12),
      ]);

      expect(small.length, large.length);
      expect(small.length, 2);
    });

    test('a looser tolerance merges lines a tighter one separates', () {
      final glyphs = [
        ...line('AB', centerY: 100),
        ...line('CD', centerY: 106),
      ];

      const tight = RowClusterer(toleranceFactor: 0.5);
      const loose = RowClusterer(toleranceFactor: 1.5);

      expect(tight.cluster(glyphs), hasLength(2));
      expect(loose.cluster(glyphs), hasLength(1));
    });
  });

  group('GlyphRow', () {
    test('reconstructs word gaps the glyph source dropped', () {
      // Whitespace is not in the input at all; the space has to be inferred
      // from the horizontal gap between inked glyphs.
      final rows = clusterer.cluster([
        glyph('A', x: 0, centerY: 50),
        glyph('B', x: 5, centerY: 50),
        glyph('C', x: 40, centerY: 50),
      ]);

      expect(rows.single.text, 'AB C');
    });

    test('exposes its bounding box', () {
      final rows = clusterer.cluster([
        glyph('A', x: 10, centerY: 50, width: 5, size: 10),
        glyph('B', x: 100, centerY: 50, width: 7, size: 10),
      ]);
      final row = rows.single;

      expect(row.left, 10);
      expect(row.right, 107);
      expect(row.top, 45);
      expect(row.bottom, 55);
      expect(row.height, 10);
    });
  });

  group('maskStructure', () {
    test('keeps layout while removing content', () {
      expect(
        maskStructure('SWIGGY BLR 04/05/26 1,234.50'),
        'AAAAAA AAA 99/99/99 9,999.99',
      );
    });

    test('distinguishes case but not identity', () {
      expect(maskStructure('Zomato'), 'Aaaaaa');
    });

    test('leaves punctuation and spacing alone', () {
      expect(maskStructure('RAZORPAY*ZOMATO'), 'AAAAAAAA*AAAAAA');
      expect(maskStructure('  a  '), '  a  ');
    });

    test('is length preserving, so columns still line up', () {
      const samples = ['SWIGGY 800.00', 'a', '', '₹1,234.50 Dr'];
      for (final sample in samples) {
        expect(maskStructure(sample).length, sample.length);
      }
    });
  });
}
