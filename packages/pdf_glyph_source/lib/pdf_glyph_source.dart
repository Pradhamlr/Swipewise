/// PDF bytes -> positioned glyph runs, via PDFium over `dart:ffi`.
///
/// This package owns the native boundary and nothing else. It performs no
/// clustering, no column detection and no issuer-specific logic — those live
/// in `statement_parser`, which starts at `GlyphRun` and needs no PDF engine.
///
/// Pure Dart despite the FFI: `pdfrx_engine` has no Flutter dependency, so the
/// whole extraction path runs under `dart run` and on CI without a device.
library pdf_glyph_source;

export 'src/coordinates.dart';
export 'src/pdfium_glyph_source.dart';
