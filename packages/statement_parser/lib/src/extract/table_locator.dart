import 'package:statement_parser/src/geometry/glyph_row.dart';
import 'package:statement_parser/src/normalize/date_parser.dart';

/// A stretch of one page that looks like the body of a transaction table.
class TableRegion {
  const TableRegion({
    required this.pageIndex,
    required this.rows,
    required this.anchorRows,
  });

  final int pageIndex;

  /// Every row in the band, continuations included. Extraction runs over
  /// these so a wrapped descriptor can fold into the row above it.
  final List<GlyphRow> rows;

  /// Only the rows that begin with a date. Column detection runs over these,
  /// because a continuation line has no amount and no date and would blur the
  /// very boundaries the histogram is looking for.
  final List<GlyphRow> anchorRows;

  double get top => rows.first.centerY;
  double get bottom => rows.last.centerY;

  @override
  String toString() => 'TableRegion(page $pageIndex, ${rows.length} rows, '
      '${anchorRows.length} dated, y ${top.toStringAsFixed(0)}'
      '-${bottom.toStringAsFixed(0)})';
}

/// Finds transaction tables without being told where they are.
///
/// Hand-fed page numbers and y ranges do not survive contact with a second
/// statement: the table starts lower when the address block is longer, and it
/// spills onto different pages in different months. So the table is located by
/// what it *is* rather than where it sits — a run of rows that begin with a
/// parseable date.
///
/// That test is deliberately cheap and deliberately strict. Page furniture,
/// summary boxes and marketing copy do not begin with a date; transaction rows
/// almost always do. Requiring several in a row stops a single dated line in a
/// header ("Statement date: 05-08-26") from being mistaken for a table.
class TableLocator {
  const TableLocator({this.minAnchorRows = 3});

  /// How many dated rows a page needs before it counts as holding a table.
  final int minAnchorRows;

  List<TableRegion> locate(List<GlyphRow> rows) {
    final byPage = <int, List<GlyphRow>>{};
    for (final row in rows) {
      byPage.putIfAbsent(row.pageIndex, () => []).add(row);
    }

    final regions = <TableRegion>[];
    for (final page in byPage.keys.toList()..sort()) {
      final pageRows = byPage[page]!
        ..sort((a, b) => a.centerY.compareTo(b.centerY));

      final anchors = pageRows.where((r) => startsWithDate(r.text)).toList();
      if (anchors.length < minAnchorRows) continue;

      final from = anchors.first.centerY;
      final to = anchors.last.centerY;

      // Include everything between the first and last dated row so wrapped
      // descriptors come along. Trailing continuations after the final dated
      // row are picked up by a small tolerance below it.
      final slack = _medianRowSpacing(anchors);
      final band = pageRows
          .where((r) => r.centerY >= from && r.centerY <= to + slack)
          .toList();

      regions.add(
        TableRegion(pageIndex: page, rows: band, anchorRows: anchors),
      );
    }
    return regions;
  }

  static double _medianRowSpacing(List<GlyphRow> anchors) {
    if (anchors.length < 2) return 0;
    final gaps = <double>[
      for (var i = 1; i < anchors.length; i++)
        anchors[i].centerY - anchors[i - 1].centerY,
    ]..sort();
    return gaps[gaps.length ~/ 2];
  }
}

/// Does this row begin with something that parses as a date?
///
/// Tries the leading whitespace-delimited token first, then leading substrings
/// — word-space reconstruction sometimes leaves a row unspaced, and a date
/// welded to the descriptor behind it still has to be recognised.
bool startsWithDate(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return false;

  final token = trimmed.split(RegExp(r'\s')).first;
  if (parseStatementDate(token) != null) return true;

  for (final length in const [10, 9, 8, 6]) {
    if (trimmed.length < length) continue;
    if (parseStatementDate(trimmed.substring(0, length)) != null) return true;
  }
  return false;
}
