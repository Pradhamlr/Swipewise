import 'package:statement_parser/src/model/glyph_run.dart';

/// The seam between the platform and the parser.
///
/// The only Flutter-coupled step in Layer 1 is turning PDF bytes into
/// positioned glyphs — `pdfrx` is a Flutter plugin binding PDFium over FFI and
/// cannot run in a pure-Dart CI job. So it does not live here. The app supplies
/// an implementation; tests supply [ReplayGlyphSource].
// A seam with several implementations (pdfrx, OCR, replay), not a function in
// disguise — it stays an interface even while it has one member.
// ignore: one_member_abstracts
abstract interface class GlyphSource {
  /// Extract positioned glyph runs for the whole document.
  ///
  /// [password] is derived and tried entirely on device — issuers key their
  /// statements on DOB / name / card-last-4 combinations, so the try-list is
  /// built locally from user hints and never leaves the device.
  /// Implementations must throw a password-specific error the caller
  /// can distinguish from a corrupt-file error, so the UI can re-prompt rather
  /// than fail the import.
  Future<List<GlyphRun>> extract({String? password});
}

/// Replays a committed glyph dump. This is what makes the pipeline testable
/// without a PDF engine, a device, or a real statement.
class ReplayGlyphSource implements GlyphSource {
  const ReplayGlyphSource(this.runs);

  /// Rehydrate from the JSON produced by the debug stage dump.
  factory ReplayGlyphSource.fromJson(List<dynamic> json) => ReplayGlyphSource(
        json
            .map((e) => GlyphRun.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  final List<GlyphRun> runs;

  @override
  Future<List<GlyphRun>> extract({String? password}) async => runs;
}
