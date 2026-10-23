import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../scope.dart';
import 'metrics.dart';

/// How many bytes one row of the hex view shows.
const int hexBytesPerRow = 16;

/// The widest a hex row is, in character cells: the offset, two groups of
/// eight bytes, and the ASCII column between bars.
const int hexRowCells = 8 + 2 + 23 + 2 + 23 + 2 + hexBytesPerRow + 2;

/// The parts of one row of a hex dump.
typedef HexRow = ({String offset, String left, String right, String ascii});

/// The parts of row [row] of [bytes], 16 bytes to a row.
///
/// The offset is eight hex digits. The bytes are two groups of eight, each
/// padded to the same width so a short last row still lines up. The ASCII
/// column shows `.` for anything that is not printable.
HexRow hexRow(Uint8List bytes, int row) {
  final first = row * hexBytesPerRow;
  final last = math.min(first + hexBytesPerRow, bytes.length);
  String group(int from) {
    final digits = <String>[
      for (var i = from; i < from + 8 && i < last; i++)
        bytes[i].toRadixString(16).padLeft(2, '0'),
    ];
    return digits.join(' ').padRight(23);
  }

  return (
    offset: first.toRadixString(16).padLeft(8, '0'),
    left: group(first),
    right: group(first + 8),
    ascii: String.fromCharCodes([
      for (var i = first; i < last; i++)
        bytes[i] >= 0x20 && bytes[i] < 0x7F ? bytes[i] : 0x2E,
    ]),
  );
}

/// Row [row] of [bytes] as one line, in the layout `hexdump -C` uses.
String hexRowText(Uint8List bytes, int row) {
  final r = hexRow(bytes, row);
  return '${r.offset}  ${r.left}  ${r.right}  |${r.ascii}|';
}

/// All of [bytes] as a hex dump, one row to a line.
String hexDump(Uint8List bytes) {
  final rows = (bytes.length + hexBytesPerRow - 1) ~/ hexBytesPerRow;
  return [for (var i = 0; i < rows; i++) hexRowText(bytes, i)].join('\n');
}

/// Bytes as a hex dump: an offset, the bytes in two groups of eight, and the
/// same bytes as ASCII. Only the rows on screen are built, so a body of any
/// size opens at once.
class HexView extends StatefulWidget {
  /// Shows [bytes].
  const HexView({super.key, required this.bytes});

  /// The bytes to dump.
  final Uint8List bytes;

  @override
  State<HexView> createState() => _HexViewState();
}

class _HexViewState extends State<HexView> with BodyMetricsState<HexView> {
  static const double _padding = 12;

  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final m = metrics;
    final rows = (widget.bytes.length + hexBytesPerRow - 1) ~/ hexBytesPerRow;
    final offsetStyle = m.style.copyWith(color: tokens.faint);
    final bytesStyle = m.style.copyWith(color: tokens.text);
    final asciiStyle = m.style.copyWith(color: tokens.muted);
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.max(
          box.maxWidth,
          hexRowCells * m.charWidth + _padding * 2,
        );
        return SelectionArea(
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: ListView.builder(
                itemExtent: m.lineHeight,
                itemCount: rows,
                padding: const EdgeInsets.symmetric(
                  horizontal: _padding,
                  vertical: 8,
                ),
                addAutomaticKeepAlives: false,
                itemBuilder: (context, row) {
                  final r = hexRow(widget.bytes, row);
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${r.offset}  ', style: offsetStyle),
                        TextSpan(
                          text: '${r.left}  ${r.right}',
                          style: bytesStyle,
                        ),
                        TextSpan(text: '  |', style: offsetStyle),
                        TextSpan(text: r.ascii, style: asciiStyle),
                        TextSpan(text: '|', style: offsetStyle),
                      ],
                    ),
                    style: m.style,
                    strutStyle: m.strut,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    textScaler: TextScaler.noScaling,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
