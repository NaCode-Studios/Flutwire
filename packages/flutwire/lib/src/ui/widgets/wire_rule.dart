import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';

/// A hairline with a short length of copper wire and its node at the left end,
/// the shape of the logo's crossbar. It closes the header of a screen.
class WireRule extends StatelessWidget {
  /// Creates the rule.
  const WireRule({super.key});

  /// How tall the rule is, so a header can reserve the room for it.
  static const double height = 6;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _WirePainter(context.fw.line)),
  );
}

class _WirePainter extends CustomPainter {
  _WirePainter(this.line);

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas
      ..drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      )
      ..drawLine(
        Offset(0, y),
        Offset(18, y),
        Paint()
          ..color = FlutwireTokens.copper
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(Offset(21, y), 2.6, Paint()..color = FlutwireTokens.copper);
  }

  @override
  bool shouldRepaint(_WirePainter old) => old.line != line;
}
