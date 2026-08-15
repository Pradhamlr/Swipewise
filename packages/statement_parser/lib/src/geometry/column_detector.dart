import 'package:statement_parser/src/geometry/glyph_row.dart';
import 'package:statement_parser/src/model/glyph_run.dart';

/// Where the columns of a statement table sit, in PDF x coordinates.
class ColumnLayout {
  const ColumnLayout({
    required this.boundaries,
    required this.left,
    required this.right,
  });

  /// x positions separating adjacent columns, ascending. A layout with two
  /// boundaries describes three columns.
  final List<double> boundaries;

  /// Outer edges of the detected content.
  final double left;
  final double right;

  int get columnCount => boundaries.length + 1;

  /// Which column an x coordinate falls in.
  int columnAt(double x) {
    for (var i = 0; i < boundaries.length; i++) {
      if (x < boundaries[i]) return i;
    }
    return boundaries.length;
  }

  /// Split a row into per-column cells.
  ///
  /// A cell is itself a [GlyphRow], so the adaptive word-spacing logic runs
  /// per cell rather than per line. That is strictly better: a cell's glyphs
  /// share a font and pitch, whereas a whole row mixes a small descriptor with
  /// a large right-aligned amount, and one threshold cannot serve both.
  ///
  /// Columns with no glyphs on this row come back null rather than empty, so a
  /// caller can tell "this field is blank" from "this field is a blank string".
  List<GlyphRow?> cells(GlyphRow row) {
    final buckets = List.generate(columnCount, (_) => <GlyphRun>[]);
    for (final glyph in row.glyphs) {
      // Key on the glyph's centre: a character straddling a boundary belongs
      // to whichever column holds most of it.
      buckets[columnAt(glyph.x + glyph.width / 2)].add(glyph);
    }
    return [
      for (final bucket in buckets)
        if (bucket.isEmpty)
          null
        else
          GlyphRow(pageIndex: row.pageIndex, glyphs: bucket),
    ];
  }

  @override
  String toString() {
    final at = boundaries.map((b) => b.toStringAsFixed(1)).join(', ');
    return 'ColumnLayout($columnCount columns, boundaries: $at)';
  }
}

/// Finds column boundaries by looking for vertical whitespace that persists
/// across many rows.
///
/// A single row has gaps everywhere — between words, around punctuation. What
/// makes a gap a *column* boundary is that the rows agree about it: nearly
/// every row in a table leaves the same x band empty. So bin the x axis, count
/// how many rows leave each bin clear, and take the wide bands where almost
/// all of them do.
///
/// Feed this only the rows of the table body. Page headers and footers span
/// different x ranges and, mixed in, they erode exactly the bands being looked
/// for.
class ColumnDetector {
  const ColumnDetector({
    this.binWidth = 1.5,
    this.minGapWidth = 5,
    this.minClearFraction = 0.9,
    this.minGapPitchRatio = 2,
  });

  /// Resolution of the x-axis histogram, in points.
  final double binWidth;

  /// How wide a clear band must be to count as a column boundary rather than
  /// an inter-word space, in points.
  final double minGapWidth;

  /// Fraction of rows that must leave a bin clear for it to be a separator.
  /// Below 1.0 so that one long unwrapped descriptor cannot erase a boundary
  /// the rest of the table agrees on.
  final double minClearFraction;

  /// How much wider than a row's own letter pitch the gap at a boundary must
  /// be, measured on the rows that actually straddle it.
  ///
  /// The histogram alone is not enough. A **right-aligned numeric column**
  /// produces false interior boundaries: amounts of differing digit-length
  /// leave a vertical band that happens to be clear on every row, and no
  /// amount of tuning the clear-fraction distinguishes that from a real gap.
  /// What does distinguish it is width — a true column gap is several
  /// characters wide, while the coincidental band inside `1,234.50` is about
  /// one character wide.
  final double minGapPitchRatio;

  ColumnLayout detect(List<GlyphRow> rows) {
    if (rows.isEmpty) {
      return const ColumnLayout(boundaries: [], left: 0, right: 0);
    }

    var left = double.infinity;
    var right = double.negativeInfinity;
    for (final row in rows) {
      if (row.left < left) left = row.left;
      if (row.right > right) right = row.right;
    }
    if (!(right > left)) {
      return ColumnLayout(boundaries: const [], left: left, right: right);
    }

    final binCount = ((right - left) / binWidth).ceil() + 1;
    final clearRows = List<int>.filled(binCount, 0);

    for (final row in rows) {
      final occupied = List<bool>.filled(binCount, false);
      for (final glyph in row.glyphs) {
        final from = ((glyph.x - left) / binWidth).floor();
        final to = ((glyph.right - left) / binWidth).ceil();
        for (var i = from < 0 ? 0 : from; i <= to && i < binCount; i++) {
          occupied[i] = true;
        }
      }
      for (var i = 0; i < binCount; i++) {
        if (!occupied[i]) clearRows[i]++;
      }
    }

    final threshold = rows.length * minClearFraction;
    final minBins = (minGapWidth / binWidth).ceil();

    final boundaries = <double>[];
    var runStart = -1;
    for (var i = 0; i <= binCount; i++) {
      final isSeparator = i < binCount && clearRows[i] >= threshold;
      if (isSeparator) {
        if (runStart < 0) runStart = i;
        continue;
      }
      if (runStart >= 0) {
        final runEnd = i - 1;
        // Runs touching either edge are the margins, not column gaps.
        final touchesEdge = runStart == 0 || i == binCount;
        if (!touchesEdge && runEnd - runStart + 1 >= minBins) {
          final centre = (runStart + runEnd + 1) / 2;
          boundaries.add(left + centre * binWidth);
        }
        runStart = -1;
      }
    }

    return ColumnLayout(
      boundaries: _pruneNarrowBoundaries(boundaries, rows),
      left: left,
      right: right,
    );
  }

  /// Drop candidate boundaries whose real gap is no wider than ordinary
  /// letter spacing on the rows that straddle them.
  List<double> _pruneNarrowBoundaries(
    List<double> candidates,
    List<GlyphRow> rows,
  ) {
    final kept = <double>[];

    for (final boundary in candidates) {
      final gaps = <double>[];
      final pitches = <double>[];

      for (final row in rows) {
        GlyphRun? lastLeft;
        GlyphRun? firstRight;
        for (final glyph in row.glyphs) {
          if (glyph.x + glyph.width / 2 < boundary) {
            lastLeft = glyph;
          } else {
            firstRight ??= glyph;
          }
        }
        if (lastLeft == null || firstRight == null) continue;
        gaps.add(firstRight.x - lastLeft.right);
        pitches.add(row.typicalPitch);
      }

      // Nothing straddles it, so there is no evidence against it.
      if (gaps.isEmpty) {
        kept.add(boundary);
        continue;
      }

      gaps.sort();
      pitches.sort();
      final medianGap = gaps[gaps.length ~/ 2];
      final medianPitch = pitches[pitches.length ~/ 2];

      final wideEnough = medianGap >= minGapWidth &&
          (medianPitch <= 0 || medianGap >= medianPitch * minGapPitchRatio);
      if (wideEnough) kept.add(boundary);
    }

    return kept;
  }
}
