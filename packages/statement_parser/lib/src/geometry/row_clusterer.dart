import 'package:statement_parser/src/geometry/glyph_row.dart';
import 'package:statement_parser/src/model/glyph_run.dart';

/// Groups positioned glyphs into printed lines.
///
/// The whole geometric core rests on one observation: **glyphs on a printed
/// line share a baseline, not a centre and not a top edge.**
///
/// That is not a stylistic preference, it is typography. A `.` inks a box a
/// fifth the height of a digit, sitting on the same baseline, so its *centre*
/// is half a line lower than the digit's. Cluster on centres and the decimal
/// points peel off into a row of their own — which is exactly what happened on
/// a real statement, turning `1443.98` into `144398` and `30.00` into `3000`.
/// The same argument covers mixed font sizes: a 7pt descriptor and a 12pt
/// amount on one row share a baseline exactly and a centre not at all.
///
/// Descenders are the one imperfection — `g`, `p`, `y` ink below the baseline
/// — but that error is about a fifth of a line, where the centre error for a
/// full stop is more than half, so the tolerance absorbs it comfortably.
///
/// Tolerance is expressed as a *fraction of glyph height* rather than an
/// absolute number of points, because statements are typeset at wildly
/// different sizes and any absolute value would be tuned to one issuer.
class RowClusterer {
  const RowClusterer({this.toleranceFactor = 0.6});

  /// Two glyphs join the same row when their centres are within
  /// `toleranceFactor * medianGlyphHeight` of each other.
  ///
  /// Too small and a single line fragments into several rows; too large and
  /// adjacent lines merge. Both failures are visible in the extraction score,
  /// which is why this is a knob rather than a constant.
  final double toleranceFactor;

  /// Cluster [runs] into rows, page by page, in reading order.
  ///
  /// Rows come back ordered top to bottom within a page, pages in order, and
  /// glyphs within a row left to right.
  List<GlyphRow> cluster(List<GlyphRun> runs) {
    if (runs.isEmpty) return const [];

    final byPage = <int, List<GlyphRun>>{};
    for (final run in runs) {
      byPage.putIfAbsent(run.pageIndex, () => []).add(run);
    }

    final pages = byPage.keys.toList()..sort();
    final rows = <GlyphRow>[];
    for (final page in pages) {
      rows.addAll(_clusterPage(page, byPage[page]!));
    }
    return rows;
  }

  List<GlyphRow> _clusterPage(int pageIndex, List<GlyphRun> runs) {
    final tolerance = _medianHeight(runs) * toleranceFactor;

    final sorted = [...runs]..sort((a, b) => a.bottom.compareTo(b.bottom));

    final rows = <GlyphRow>[];
    var current = <GlyphRun>[sorted.first];
    // Compared against the running mean rather than the first glyph, so a row
    // that drifts slightly across the page does not shed its right-hand end.
    var runningBaseline = sorted.first.bottom;

    for (var i = 1; i < sorted.length; i++) {
      final run = sorted[i];
      if ((run.bottom - runningBaseline).abs() <= tolerance) {
        current.add(run);
        runningBaseline = current.map((g) => g.bottom).reduce((a, b) => a + b) /
            current.length;
      } else {
        rows.add(_finishRow(pageIndex, current));
        current = <GlyphRun>[run];
        runningBaseline = run.bottom;
      }
    }
    rows.add(_finishRow(pageIndex, current));

    return rows;
  }

  static GlyphRow _finishRow(int pageIndex, List<GlyphRun> glyphs) {
    final ordered = [...glyphs]..sort((a, b) => a.x.compareTo(b.x));
    return GlyphRow(pageIndex: pageIndex, glyphs: ordered);
  }

  static double _medianHeight(List<GlyphRun> runs) {
    final heights = runs.map((r) => r.height).toList()..sort();
    final median = heights[heights.length ~/ 2];
    // Degenerate fixtures (all zero-height) would otherwise make every glyph
    // its own row; fall back to something that still groups by exact centre.
    return median > 0 ? median : 1;
  }
}
