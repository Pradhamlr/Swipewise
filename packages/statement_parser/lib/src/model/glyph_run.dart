import 'package:meta/meta.dart';

/// A contiguous run of glyphs on one page, with its bounding box in PDF user
/// space (origin top-left, y increasing downward — normalize at the source if
/// the engine reports bottom-left).
///
/// This is the input contract of the whole parser. It is a plain value type on
/// purpose: it serializes to JSON, so a real statement can be reduced to a
/// glyph dump once, redacted, committed, and replayed forever in tests without
/// a PDF engine.
@immutable
class GlyphRun {
  const GlyphRun({
    required this.text,
    required this.pageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory GlyphRun.fromJson(Map<String, dynamic> json) => GlyphRun(
        text: json['text'] as String,
        pageIndex: (json['page'] as num).toInt(),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
      );

  /// Text of the run, exactly as the engine reported it. Never trimmed here —
  /// leading whitespace is positional evidence the column detector may want.
  final String text;

  /// Zero-based page this run was found on.
  final int pageIndex;

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  /// Vertical midpoint. Row clustering keys on this rather than [y] because
  /// runs on the same visual row often differ in font size and therefore in
  /// top edge.
  double get centerY => y + height / 2;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'page': pageIndex,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
      };

  @override
  String toString() =>
      'GlyphRun(p$pageIndex, ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)} '
      '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)} "$text")';

  @override
  bool operator ==(Object other) =>
      other is GlyphRun &&
      other.text == text &&
      other.pageIndex == pageIndex &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(text, pageIndex, x, y, width, height);
}
