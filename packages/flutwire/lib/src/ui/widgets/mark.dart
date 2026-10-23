import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';

/// The Flutwire mark: a wire bent into an f, with a live node at the end of its
/// crossbar. It is the same drawing as `docs/brand/flutwire-symbol.svg` and as
/// the notification icon, built from the same numbers.
class FlutwireMark extends StatelessWidget {
  /// Creates the mark, [size] logical pixels tall.
  const FlutwireMark({super.key, this.size = 24, this.color, this.nodeColor});

  /// The height. The width follows from the drawing, a little under four fifths
  /// of it.
  final double size;

  /// The colour of the wire, or the ink of the current look.
  final Color? color;

  /// The colour of the node, or copper. Pass the same colour as [color] for a
  /// flat, one-colour mark.
  final Color? nodeColor;

  /// The width of the drawing for a given height.
  static double widthFor(double height) => height * _width / _height;

  static const double _width = 292;
  static const double _height = 366;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(widthFor(size), size),
    painter: _MarkPainter(
      color ?? context.fw.ink,
      nodeColor ?? FlutwireTokens.copper,
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.wire, this.node);

  final Color wire;
  final Color node;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / FlutwireMark._height);
    final stem = Path()
      ..moveTo(88, 346)
      ..lineTo(88, 104)
      ..arcToPoint(const Offset(192, 0), radius: const Radius.circular(104))
      ..lineTo(254, 0)
      ..arcToPoint(const Offset(254, 40), radius: const Radius.circular(20))
      ..lineTo(192, 40)
      ..arcToPoint(
        const Offset(128, 104),
        radius: const Radius.circular(64),
        clockwise: false,
      )
      ..lineTo(128, 346)
      ..arcToPoint(const Offset(88, 346), radius: const Radius.circular(20))
      ..close();
    final bar = Path()
      ..moveTo(20, 116)
      ..lineTo(256, 116)
      ..lineTo(256, 156)
      ..lineTo(20, 156)
      ..arcToPoint(const Offset(20, 116), radius: const Radius.circular(20))
      ..close();
    canvas
      ..drawPath(stem, Paint()..color = wire)
      ..drawPath(bar, Paint()..color = wire)
      ..drawCircle(const Offset(256, 136), 36, Paint()..color = node);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.wire != wire || old.node != node;
}
