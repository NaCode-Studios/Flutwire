import 'package:flutter/material.dart';

/// Whether a row of the tree has a chevron, and which way it points.
enum Chevron {
  /// The node has no children.
  none,

  /// The node has children and they are hidden.
  closed,

  /// The node has children and they are shown.
  open,
}

/// Draws the guide lines of the levels above a row, and its chevron.
class GuidePainter extends CustomPainter {
  /// Creates a painter for a row at [depth].
  const GuidePainter({
    required this.depth,
    required this.step,
    required this.box,
    required this.guide,
    required this.chevron,
    required this.chevronState,
  });

  /// How many levels of guide lines to draw.
  final int depth;

  /// How far apart the guide lines are.
  final double step;

  /// The width of the box the chevron sits in.
  final double box;

  /// The colour of the guide lines.
  final Color guide;

  /// The colour of the chevron.
  final Color chevron;

  /// Which chevron to draw, if any.
  final Chevron chevronState;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var d = 0; d < depth; d++) {
      final x = d * step + box / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    if (chevronState == Chevron.none) return;
    final cx = depth * step + box / 2;
    final cy = size.height / 2;
    const r = 3.5;
    final path = Path();
    if (chevronState == Chevron.closed) {
      path
        ..moveTo(cx - r * 0.6, cy - r)
        ..lineTo(cx + r * 0.9, cy)
        ..lineTo(cx - r * 0.6, cy + r);
    } else {
      path
        ..moveTo(cx - r, cy - r * 0.6)
        ..lineTo(cx, cy + r * 0.9)
        ..lineTo(cx + r, cy - r * 0.6);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = chevron);
  }

  @override
  bool shouldRepaint(GuidePainter old) =>
      old.depth != depth ||
      old.guide != guide ||
      old.chevron != chevron ||
      old.chevronState != chevronState ||
      old.step != step ||
      old.box != box;
}
