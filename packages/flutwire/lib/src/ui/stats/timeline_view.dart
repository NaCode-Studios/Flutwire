import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../stats/stats.dart';
import '../../util/format.dart';
import '../scope.dart';

/// The latest calls on one time line, one row each, so that the ones that were
/// in flight together can be seen to overlap. A bar is pale while the call
/// waited for its answer and solid while the answer came in.
class TimelineView extends StatelessWidget {
  /// Creates the view for [waterfall]. [onOpen] opens the call with an id.
  const TimelineView({
    super.key,
    required this.waterfall,
    required this.onOpen,
  });

  /// What to draw.
  final Waterfall waterfall;

  /// Opens a call.
  final ValueChanged<int> onOpen;

  /// The width of the column that names the calls.
  static const double _labels = 116;

  /// The height of a row.
  static const double _rowHeight = 30;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final ticks = timeTicks(waterfall.span);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    Text(
                      s.statsPeak(waterfall.peak),
                      style: t.body(size: 12, color: t.muted),
                    ),
                    if (waterfall.isCut)
                      Text(
                        s.statsShowingLatest(
                          waterfall.rows.length,
                          waterfall.total,
                        ),
                        style: t.body(size: 12, color: t.faint),
                      ),
                  ],
                ),
              ),
              _Legend(label: s.statsWaiting, solid: false),
              const SizedBox(width: 10),
              _Legend(label: s.statsReceiving, solid: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const SizedBox(width: _labels),
              Expanded(
                child: SizedBox(
                  height: 20,
                  child: CustomPaint(
                    painter: _AxisPainter(
                      span: waterfall.span,
                      ticks: ticks,
                      line: t.line,
                      style: t.mono(size: 10, color: t.faint, height: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: t.line),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            itemExtent: _rowHeight,
            itemCount: waterfall.rows.length,
            itemBuilder: (context, index) {
              final row = waterfall.rows[index];
              final call = row.call;
              return Semantics(
                button: true,
                label:
                    '${call.method} ${call.pathAndQuery}, '
                    '${formatDuration(row.length)}',
                child: InkWell(
                  onTap: () => onOpen(call.id),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _labels,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${call.method}  ${call.pathAndQuery}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.mono(size: 11, color: t.text),
                          ),
                        ),
                      ),
                      Expanded(
                        child: CustomPaint(
                          size: const Size.fromHeight(_rowHeight),
                          painter: _BarPainter(
                            row: row,
                            span: waterfall.span,
                            ticks: ticks,
                            color: t.statusColor(call),
                            line: t.line,
                            pending: call.isPending,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.solid});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 8,
          decoration: BoxDecoration(
            color: t.muted.withValues(alpha: solid ? 1 : 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: t.body(size: 11, color: t.faint)),
      ],
    );
  }
}

/// How far along a time line of length [span] a moment [at] is, from 0 to 1.
double _along(Duration at, Duration span) =>
    span.inMicroseconds == 0 ? 0 : at.inMicroseconds / span.inMicroseconds;

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.span,
    required this.ticks,
    required this.line,
    required this.style,
  });

  final Duration span;
  final List<Duration> ticks;
  final Color line;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final x = _along(tick, span) * size.width;
      canvas.drawLine(
        Offset(x, size.height - 5),
        Offset(x, size.height),
        paint,
      );
      final label = TextPainter(
        text: TextSpan(text: formatDuration(tick), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // A label stays inside the bar area, so the first sits at the start and
      // the last ends at the end.
      final left = (x - label.width / 2).clamp(0.0, size.width - label.width);
      label
        ..paint(canvas, Offset(left, 1))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.span != span ||
      old.line != line ||
      old.style != style ||
      !listEquals(old.ticks, ticks);
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.row,
    required this.span,
    required this.ticks,
    required this.color,
    required this.line,
    required this.pending,
  });

  final WaterfallRow row;
  final Duration span;
  final List<Duration> ticks;
  final Color color;
  final Color line;
  final bool pending;

  /// A call that took no time still gets a bar that can be seen and tapped.
  static const double _thinnest = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final tick in ticks) {
      final x = (_along(tick, span) * size.width).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final start = _along(row.offset, span) * size.width;
    final end = _along(row.end, span) * size.width;
    final left = start.clamp(0.0, size.width - _thinnest);
    final right = end.clamp(left + _thinnest, size.width);
    const height = 10.0;
    final top = (size.height - height) / 2;
    final radius = const Radius.circular(3);
    final solid = pending ? color.withValues(alpha: 0.7) : color;

    final waiting = row.waiting;
    if (waiting == null) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, top, right, top + height, radius),
        Paint()..color = solid,
      );
      return;
    }
    final answer = (_along(row.offset + waiting, span) * size.width).clamp(
      left,
      right,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromLTRBR(left, top, right, top + height, radius));
    canvas.drawRect(
      Rect.fromLTRB(left, top, answer, top + height),
      Paint()..color = color.withValues(alpha: 0.35),
    );
    canvas.drawRect(
      Rect.fromLTRB(answer, top, right, top + height),
      Paint()..color = solid,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.row != row ||
      old.span != span ||
      old.color != color ||
      old.line != line ||
      old.pending != pending ||
      !listEquals(old.ticks, ticks);
}
