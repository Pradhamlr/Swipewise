import 'package:statement_parser/statement_parser.dart';

/// Convert a rectangle in PDF user space into a [GlyphRun].
///
/// PDF page coordinates put the origin at the **bottom-left** with y pointing
/// up, so `top > bottom`. [GlyphRun] uses the opposite convention — origin
/// top-left, y pointing down — because every downstream stage (row clustering,
/// column histograms, reading order) is easier to reason about when y grows in
/// reading direction.
///
/// The flip needs [pageHeight] and is the single place this conversion
/// happens. Keeping it a free function means it can be tested without PDFium.
GlyphRun toGlyphRun({
  required String text,
  required int pageIndex,
  required double pageHeight,
  required double left,
  required double top,
  required double right,
  required double bottom,
}) {
  return GlyphRun(
    text: text,
    pageIndex: pageIndex,
    x: left,
    y: pageHeight - top,
    width: right - left,
    height: top - bottom,
  );
}
