import 'package:flutter/material.dart';

import '../scope.dart';

/// The Flutwire glyph: two ends of a wire and the tap between them. It is drawn
/// in one flat colour, the same shape as the notification icon.
class FlutwireMark extends StatelessWidget {
  /// Creates the glyph at [size] logical pixels.
  const FlutwireMark({super.key, this.size = 24, this.color});

  /// The width and height.
  final double size;

  /// The colour, or the muted ink of the current look.
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MarkPainter(color ?? context.fw.muted),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(Offset(4.5 * unit, 14.5 * unit), 2.5 * unit, fill)
      ..drawCircle(Offset(19.5 * unit, 14.5 * unit), 2.5 * unit, fill)
      ..drawCircle(Offset(12 * unit, 4.5 * unit), 2.25 * unit, fill)
      ..drawLine(
        Offset(7 * unit, 14.5 * unit),
        Offset(17 * unit, 14.5 * unit),
        stroke,
      )
      ..drawLine(
        Offset(12 * unit, 6.75 * unit),
        Offset(12 * unit, 14.5 * unit),
        stroke,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
