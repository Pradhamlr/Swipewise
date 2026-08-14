import 'package:statement_parser/src/geometry/glyph_row.dart';
import 'package:statement_parser/src/model/glyph_run.dart';

/// Groups positioned glyphs into printed lines.
///
/// The whole geometric core rests on one observation: glyphs on the same
/// printed line share a vertical centre far more reliably than they share a
/// top edge. A statement row mixes font sizes — a small superscript in a
/// descriptor, a larger amount — and clustering on `y` splits those apart
/// while clustering on [GlyphRun.centerY] keeps them together.
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

    final sorted = [...runs]..sort((a, b) => a.centerY.compareTo(b.centerY));

    final rows = <GlyphRow>[];
    var current = <GlyphRun>[sorted.first];
    // Compared against the running mean rather than the first glyph, so a row
    // that drifts slightly across the page does not shed its right-hand end.
    var runningCenter = sorted.first.centerY;

    for (var i = 1; i < sorted.length; i++) {
      final run = sorted[i];
      if ((run.centerY - runningCenter).abs() <= tolerance) {
        current.add(run);
        runningCenter = current.map((g) => g.centerY).reduce((a, b) => a + b) /
            current.length;
      } else {
        rows.add(_finishRow(pageIndex, current));
        current = <GlyphRun>[run];
        runningCenter = run.centerY;
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
