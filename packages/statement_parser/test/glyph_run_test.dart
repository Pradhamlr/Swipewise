import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

void main() {
  group('GlyphRun', () {
    const run = GlyphRun(
      text: 'SWIGGY BANGALORE',
      pageIndex: 1,
      x: 72.5,
      y: 310.25,
      width: 96,
      height: 8.5,
    );

    test('survives a JSON round trip', () {
      expect(GlyphRun.fromJson(run.toJson()), equals(run));
    });

    test('centerY sits at the vertical midpoint', () {
      // Row clustering keys on this, not on y — see glyph_run.dart.
      expect(run.centerY, closeTo(314.5, 1e-9));
    });

    test('right and bottom extend the box', () {
      expect(run.right, closeTo(168.5, 1e-9));
      expect(run.bottom, closeTo(318.75, 1e-9));
    });
  });

  test('ReplayGlyphSource returns exactly what it was given', () async {
    final source = ReplayGlyphSource.fromJson(<dynamic>[
      <String, dynamic>{
        'text': '05/08/26',
        'page': 0,
        'x': 40.0,
        'y': 200.0,
        'w': 34.0,
        'h': 8.0,
      },
    ]);

    final runs = await source.extract();
    expect(runs, hasLength(1));
    expect(runs.single.text, '05/08/26');
  });
}
