import 'package:pdf_glyph_source/src/coordinates.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:statement_parser/statement_parser.dart';

/// A [GlyphSource] backed by PDFium through `dart:ffi`.
///
/// Emits **one [GlyphRun] per character**, not per word or per line. PDFium can
/// group characters itself via `loadStructuredText`, but that applies its own
/// reading-order and line-segmentation analysis — which is exactly the work
/// this project exists to do by hand. Taking the rawest available signal keeps
/// every geometric decision in `statement_parser`, where it is measurable.
class PdfiumGlyphSource implements GlyphSource {
  const PdfiumGlyphSource.file(this.path, {this.cacheDirectoryPath});

  /// Path to the PDF on disk.
  final String path;

  /// Writable directory PDFium may use for its cache.
  ///
  /// Must be supplied on Android. Left to itself, `pdfrxInitialize` falls back
  /// to `Platform.environment['HOME']!` — and Android sets no `HOME`, so that
  /// `!` throws "Null check operator used on a null value" with nothing in the
  /// message to suggest a cache directory was ever involved.
  ///
  /// It cannot be inherited from the main isolate either: the library keeps
  /// its configuration in statics, and statics are per-isolate. Whoever spawns
  /// the isolate has to hand the path across explicitly.
  final String? cacheDirectoryPath;

  @override
  Future<List<GlyphRun>> extract({String? password}) async {
    await pdfrxInitialize(tmpPath: cacheDirectoryPath);

    final document = await PdfDocument.openFile(
      path,
      passwordProvider: createSimplePasswordProvider(password),
    );

    try {
      final runs = <GlyphRun>[];
      for (final page in document.pages) {
        final raw = await page.loadText();
        if (raw == null) continue;

        final pageIndex = page.pageNumber - 1;
        final pageHeight = page.height;
        final text = raw.fullText;
        final rects = raw.charRects;

        final count = text.length < rects.length ? text.length : rects.length;
        for (var i = 0; i < count; i++) {
          final char = text[i];

          // Whitespace carries no geometry PDFium can be trusted on — spaces
          // and newlines come back with degenerate (zero-height) rects. Gaps
          // between words are recoverable from neighbouring x positions, which
          // is how the column detector finds them anyway.
          if (char.trim().isEmpty) continue;

          final rect = rects[i];
          if (rect.isEmpty) continue;

          runs.add(
            toGlyphRun(
              text: char,
              pageIndex: pageIndex,
              pageHeight: pageHeight,
              left: rect.left,
              top: rect.top,
              right: rect.right,
              bottom: rect.bottom,
            ),
          );
        }
      }
      return runs;
    } finally {
      await document.dispose();
    }
  }
}
