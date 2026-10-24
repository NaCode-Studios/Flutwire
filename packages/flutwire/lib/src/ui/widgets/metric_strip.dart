import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../stats/stats.dart';
import '../../util/format.dart';
import '../scope.dart';

/// Four numbers that say how a session is going: how many calls, how many went
/// wrong, how long they take on average, and how much they moved. The statistics
/// page has the rest.
///
/// They stand in a row when each has the room for its label, and in two rows of
/// two when the screen, the panel or the text size does not give it.
class MetricStrip extends StatelessWidget {
  /// Creates the strip for [calls].
  const MetricStrip({super.key, required this.calls});

  /// The calls the numbers are about.
  final List<FlutwireCall> calls;

  static const double _labelSize = 9.5;

  /// What a label needs besides its own width, so that two never touch.
  static const double _gap = 4;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final stats = SessionStats.of(calls, slowest: 0);
    final failed = stats.failed;
    final average = stats.average;
    final metrics = [
      _Metric(label: s.statCalls, value: '${stats.total}'),
      _Metric(
        label: s.statFailed,
        value: '$failed',
        color: failed > 0 ? t.error : null,
      ),
      _Metric(
        label: s.statAverage,
        value: average == null ? '·' : formatDuration(average),
      ),
      _Metric(
        label: s.statTransferred,
        value: formatBytes(stats.bytesTransferred),
      ),
    ];
    final widest = _widestLabel(context, [for (final m in metrics) m.label]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth / metrics.length >= widest + _gap) {
            return Row(children: [for (final m in metrics) Expanded(child: m)]);
          }
          return Column(
            children: [
              Row(
                children: [for (final m in metrics.take(2)) Expanded(child: m)],
              ),
              const SizedBox(height: 10),
              Row(
                children: [for (final m in metrics.skip(2)) Expanded(child: m)],
              ),
            ],
          );
        },
      ),
    );
  }

  /// The width of the longest of [labels] as the strip writes them.
  static double _widestLabel(BuildContext context, List<String> labels) {
    final style = context.fw.label(size: _labelSize);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label.toUpperCase(), style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: t.label(size: MetricStrip._labelSize),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: t.mono(
              size: 18,
              weight: FontWeight.w600,
              color: color ?? t.ink,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}
