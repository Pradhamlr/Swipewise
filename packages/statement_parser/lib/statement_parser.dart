/// Pure-Dart statement parsing pipeline.
///
/// The pipeline is deliberately split at the glyph boundary:
///
///   PDF bytes --(Flutter/FFI, lives in app/)--> `GlyphRun` --(this package)-->
///   rows -> columns -> issuer adapter -> transactions
///
/// Everything downstream of `GlyphRun` is pure Dart and testable on CI from a
/// committed JSON glyph dump, with no PDF engine and no device.
///
/// The split lands at the glyph rather than at the PDF because every hard part
/// — row clustering, column histograms, issuer adapters, amount normalization —
/// is downstream of it, and a glyph dump doubles as a replayable fixture that
/// keeps real bank documents out of the repository entirely.
library statement_parser;

export 'src/debug/structure_mask.dart';
export 'src/eval/extraction_score.dart';
export 'src/eval/labeled_statement.dart';
export 'src/geometry/glyph_row.dart';
export 'src/geometry/row_clusterer.dart';
export 'src/model/glyph_run.dart';
export 'src/model/money.dart';
export 'src/model/statement_transaction.dart';
export 'src/source/glyph_source.dart';
