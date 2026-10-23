import 'dart:math' as math;
import 'dart:typed_data';

import 'metrics.dart' show bodyMaxRowChars;

/// How a text is cut into rows of fixed height.
///
/// A row is a slice of one line. A line becomes several rows when it is longer
/// than [bodyMaxRowChars], or, in wrap mode, longer than the width of the
/// screen. Cutting the text up front is what lets the code view be a plain
/// virtualised list: the n-th row is at `n * lineHeight`, whatever the text is.
final class CodeLayout {
  CodeLayout._(
    this.text,
    this._starts,
    this._ends,
    this._lines,
    this.lineCount,
    this.maxWeight,
  );

  /// Cuts [text] into rows.
  ///
  /// With [maxCells] set, a row also ends when it would be wider than that many
  /// character cells, which is how lines are wrapped: the face is monospaced,
  /// so a cell count is an exact width. Wide characters count for more than one
  /// cell, so that a row of Japanese text does not overflow the screen.
  factory CodeLayout.build(
    String text, {
    int? maxCells,
    int maxChars = bodyMaxRowChars,
  }) {
    final limit = maxCells == null ? 1 << 30 : maxCells * 100;
    final starts = <int>[];
    final ends = <int>[];
    final lines = <int>[];
    var widest = 0;
    final length = text.length;
    var pos = 0;
    var line = 0;
    // A trailing line break ends the last line; it does not open an empty one.
    while (pos < length) {
      var lineEnd = text.indexOf('\n', pos);
      if (lineEnd < 0) lineEnd = length;
      var contentEnd = lineEnd;
      if (contentEnd > pos && text.codeUnitAt(contentEnd - 1) == 0x0D) {
        contentEnd--;
      }
      if (contentEnd == pos) {
        starts.add(pos);
        ends.add(pos);
        lines.add(line);
      } else {
        var rowStart = pos;
        var weight = 0;
        for (var i = pos; i < contentEnd; i++) {
          final unit = text.codeUnitAt(i);
          final w = weightOf(unit);
          // Never cut between the halves of a surrogate pair.
          final isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
          if (!isLowSurrogate &&
              i > rowStart &&
              (weight + w > limit || i - rowStart >= maxChars)) {
            starts.add(rowStart);
            ends.add(i);
            lines.add(line);
            widest = math.max(widest, weight);
            rowStart = i;
            weight = 0;
          }
          weight += w;
        }
        starts.add(rowStart);
        ends.add(contentEnd);
        lines.add(line);
        widest = math.max(widest, weight);
      }
      line++;
      pos = lineEnd + 1;
    }
    return CodeLayout._(
      text,
      Int32List.fromList(starts),
      Int32List.fromList(ends),
      Int32List.fromList(lines),
      line,
      widest,
    );
  }

  /// How many lines [text] has, counted the way [CodeLayout.build] counts.
  static int lineCountOf(String text) {
    var count = 0;
    var pos = 0;
    while (pos < text.length) {
      final at = text.indexOf('\n', pos);
      count++;
      if (at < 0) break;
      pos = at + 1;
    }
    return count;
  }

  /// The width of one character in hundredths of a cell: a cell for anything
  /// the monospaced face draws itself, and more for the scripts that fall back
  /// to a wider face. The second half of a surrogate pair adds nothing, so an
  /// emoji weighs the same as one wide character.
  static int weightOf(int codeUnit) {
    if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) return 0;
    return codeUnit < 0x1100 ? 100 : 170;
  }

  /// The text that was cut.
  final String text;

  final Int32List _starts;
  final Int32List _ends;
  final Int32List _lines;

  /// How many lines the text has, which is the number the last row carries.
  final int lineCount;

  /// The width of the widest row, in hundredths of a cell.
  final int maxWeight;

  /// The number of rows.
  int get rowCount => _starts.length;

  /// The width of the widest row, in cells.
  double get maxCells => maxWeight / 100;

  /// The offset in [text] where [row] begins.
  int start(int row) => _starts[row];

  /// The offset in [text] where [row] ends, line break excluded.
  int end(int row) => _ends[row];

  /// The zero-based line [row] belongs to.
  int line(int row) => _lines[row];

  /// Whether [row] starts its line, as opposed to continuing a cut line.
  bool isFirstOfLine(int row) => row == 0 || _lines[row] != _lines[row - 1];

  /// The row that holds [offset], or the nearest row before it.
  int rowAt(int offset) {
    if (_starts.isEmpty) return 0;
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
