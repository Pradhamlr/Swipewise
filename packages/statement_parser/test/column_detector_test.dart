import 'package:statement_parser/statement_parser.dart';
import 'package:test/test.dart';

/// Build a row of glyphs laid out as fixed-width cells at given x offsets.
/// Each character advances 5pt, so a gap of 5 is an inter-word space and a gap
/// of 30 is a column boundary.
GlyphRow rowAt({
  required double centerY,
  required Map<double, String> cells,
  int page = 0,
}) {
  final glyphs = <GlyphRun>[];
  cells.forEach((startX, text) {
    for (var i = 0; i < text.length; i++) {
      if (text[i] == ' ') continue;
      glyphs.add(
        GlyphRun(
          text: text[i],
          pageIndex: page,
          x: startX + i * 5,
          y: centerY - 4,
          width: 4,
          height: 8,
        ),
      );
    }
  });
  glyphs.sort((a, b) => a.x.compareTo(b.x));
  return GlyphRow(pageIndex: page, glyphs: glyphs);
}

void main() {
  const detector = ColumnDetector();

  /// A four-column table: date, reference, description, amount.
  List<GlyphRow> table() => [
        rowAt(
          centerY: 100,
          cells: {
            20: '05-08-26',
            100: 'REF001',
            200: 'SWIGGY BLR',
            400: '800.00',
          },
        ),
        rowAt(
          centerY: 115,
          cells: {
            20: '06-08-26',
            100: 'REF002',
            200: 'AMAZON IN',
            400: '1250.50',
          },
        ),
        rowAt(
          centerY: 130,
          cells: {
            20: '07-08-26',
            100: 'REF003',
            200: 'BIGBASKET',
            400: '432.00',
          },
        ),
        rowAt(
          centerY: 145,
          cells: {
            20: '08-08-26',
            100: 'REF004',
            200: 'UBER TRIP',
            400: '199.00',
          },
        ),
      ];

  group('ColumnDetector', () {
    test('finds the boundaries the rows agree on', () {
      final layout = detector.detect(table());
      expect(layout.columnCount, 4);
      expect(layout.boundaries, hasLength(3));
    });

    test('ignores inter-word gaps inside a cell', () {
      // "SWIGGY BLR" has a single 5pt space in it. A naive gap finder would
      // call that a column.
      final layout = detector.detect(table());
      final insideDescription =
          layout.boundaries.where((b) => b > 230 && b < 280);
      expect(insideDescription, isEmpty);
    });

    test('splits a row into cells', () {
      final rows = table();
      final layout = detector.detect(rows);
      final cells = layout.cells(rows.first);

      expect(cells, hasLength(4));
      expect(cells[0]!.text, '05-08-26');
      expect(cells[1]!.text, 'REF001');
      expect(cells[2]!.text, 'SWIGGY BLR');
      expect(cells[3]!.text, '800.00');
    });

    test('an empty cell comes back null, not an empty string', () {
      final rows = [
        ...table(),
        rowAt(centerY: 160, cells: {20: '09-08-26', 400: '50.00'}),
      ];
      final layout = detector.detect(rows);
      final cells = layout.cells(rows.last);

      expect(cells[0]!.text, '09-08-26');
      expect(cells[1], isNull);
      expect(cells[2], isNull);
      expect(cells[3]!.text, '50.00');
    });

    test('one long descriptor does not erase a boundary', () {
      // The reason the clear-fraction threshold is below 1.0: a single row
      // spilling across a gap should not delete a column the rest agree on.
      final rows = [
        ...table(),
        rowAt(
          centerY: 160,
          cells: {
            20: '09-08-26',
            100: 'REF005SPILLINGRIGHTACROSS',
            400: '10.00',
          },
        ),
      ];
      final layout = detector.detect(rows);
      expect(layout.columnCount, greaterThanOrEqualTo(3));
    });

    test('a glyph straddling a boundary goes where most of it is', () {
      final rows = table();
      final layout = detector.detect(rows);
      final boundary = layout.boundaries.first;

      final straddling = GlyphRow(
        pageIndex: 0,
        glyphs: [
          GlyphRun(
            text: 'X',
            pageIndex: 0,
            x: boundary - 1,
            y: 96,
            width: 4,
            height: 8,
          ),
        ],
      );
      // Centre sits at boundary + 1, so it belongs to the right-hand column.
      expect(layout.cells(straddling)[1], isNotNull);
      expect(layout.cells(straddling)[0], isNull);
    });

    test('no rows yields an empty layout rather than throwing', () {
      final layout = detector.detect([]);
      expect(layout.columnCount, 1);
      expect(layout.boundaries, isEmpty);
    });

    test('a single column table finds no boundaries', () {
      final rows = [
        rowAt(centerY: 100, cells: {20: 'ALPHA'}),
        rowAt(centerY: 115, cells: {20: 'BRAVO'}),
      ];
      expect(detector.detect(rows).columnCount, 1);
    });
  });
}
