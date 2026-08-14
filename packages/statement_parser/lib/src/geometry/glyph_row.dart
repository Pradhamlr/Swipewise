import 'package:meta/meta.dart';
import 'package:statement_parser/src/model/glyph_run.dart';

/// A horizontal band of glyphs that share a baseline — one *printed line*.
///
/// Not a transaction. A transaction whose description wraps occupies several
/// [GlyphRow]s, and joining those back together is a later stage that needs to
/// know what the columns mean. Keeping the two apart is what lets row
/// clustering be scored on its own.
@immutable
class GlyphRow {
  GlyphRow({required this.pageIndex, required List<GlyphRun> glyphs})
      : assert(glyphs.isNotEmpty, 'a row must contain at least one glyph'),
        glyphs = List<GlyphRun>.unmodifiable(glyphs);

  final int pageIndex;

  /// Glyphs in reading order, left to right.
  final List<GlyphRun> glyphs;

  double get left => glyphs.map((g) => g.x).reduce((a, b) => a < b ? a : b);

  double get right =>
      glyphs.map((g) => g.right).reduce((a, b) => a > b ? a : b);

  double get top => glyphs.map((g) => g.y).reduce((a, b) => a < b ? a : b);

  double get bottom =>
      glyphs.map((g) => g.bottom).reduce((a, b) => a > b ? a : b);

  double get centerY => (top + bottom) / 2;

  double get height => bottom - top;

  /// Distance between the origins of adjacent glyphs — the *advance*, not the
  /// gap between ink.
  List<double> get pitches => [
        for (var i = 1; i < glyphs.length; i++) glyphs[i].x - glyphs[i - 1].x,
      ];

  /// A robust estimate of one character's advance on this row.
  ///
  /// Uses the lower median so that on short rows — where half the pairs may
  /// straddle a space — the estimate still lands on the intra-word spacing
  /// rather than on the gap.
  double get typicalPitch {
    final sorted = [...pitches]..sort();
    if (sorted.isEmpty) return 0;
    return sorted[(sorted.length - 1) ~/ 2];
  }

  /// The row's text, with a single space inserted wherever the advance between
  /// adjacent glyphs exceeds [spaceFactor] times [typicalPitch].
  ///
  /// Spaces have to be reconstructed because the glyph source drops them —
  /// PDFium reports degenerate zero-height rects for whitespace.
  ///
  /// Measuring *pitch* rather than the gap between ink matters more than it
  /// looks. Narrow glyphs — `1`, `.`, `,`, `i` — carry far less ink than they
  /// advance, so an ink gap makes an ordinary pair inside `1,234.50` look as
  /// wide as a real space, and amounts come apart into fragments. Pitch is
  /// unaffected by how much of its box a glyph happens to fill.
  String textWithSpaceFactor(double spaceFactor) {
    if (glyphs.length == 1) return glyphs.first.text;

    final pitch = typicalPitch;
    final threshold = pitch > 0 ? pitch * spaceFactor : double.infinity;
    final advances = pitches;

    final buffer = StringBuffer(glyphs.first.text);
    for (var i = 1; i < glyphs.length; i++) {
      if (advances[i - 1] > threshold) buffer.write(' ');
      buffer.write(glyphs[i].text);
    }
    return buffer.toString();
  }

  /// The advance above which a gap is a word space, chosen per row.
  ///
  /// A single fixed factor cannot serve a whole statement. Tabular digits are
  /// set at a uniform pitch, so a space stands out at barely 1.3× the norm,
  /// while a tracked-out heading has intra-word advances so wide that its
  /// spaces never reach 1.6×. Tuning one constant to fix headings breaks
  /// amounts and vice versa — which is exactly what happened when this was a
  /// constant.
  ///
  /// A transaction row's advances are not bimodal but *trimodal*: tight
  /// intra-word values, wider word spaces, and much wider column gaps. Cutting
  /// at the widest jump therefore finds the column boundary and throws away
  /// every ordinary space. What is wanted is the *lowest* convincing jump —
  /// the first real step above intra-word spacing — after which word spaces
  /// and column gaps both read as spaces, which is correct.
  ///
  /// If no jump is convincing the row is treated as one unspaced token. That
  /// is the safe failure: a missing space is recoverable downstream, an
  /// invented one splits a field in half.
  double get spaceThreshold {
    final sorted = [...pitches]..sort();
    if (sorted.length < 2) return double.infinity;

    const minRatio = 1.5;

    // Start at the lower median: intra-word pairs outnumber spaces, so the
    // boundary lies above the typical advance, never below it.
    for (var i = (sorted.length - 1) ~/ 2; i < sorted.length - 1; i++) {
      final lower = sorted[i];
      final upper = sorted[i + 1];
      if (lower <= 0) continue;
      if (upper / lower > minRatio) return (lower + upper) / 2;
    }
    return double.infinity;
  }

  /// The row's text with word spaces restored, using [spaceThreshold].
  String get text {
    if (glyphs.length == 1) return glyphs.first.text;

    final threshold = spaceThreshold;
    final advances = pitches;

    final buffer = StringBuffer(glyphs.first.text);
    for (var i = 1; i < glyphs.length; i++) {
      if (advances[i - 1] > threshold) buffer.write(' ');
      buffer.write(glyphs[i].text);
    }
    return buffer.toString();
  }

  @override
  String toString() => 'GlyphRow(p$pageIndex, y=${centerY.toStringAsFixed(1)}, '
      '${glyphs.length} glyphs, "$text")';
}
