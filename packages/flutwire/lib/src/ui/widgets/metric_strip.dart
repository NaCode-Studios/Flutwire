import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../stats/stats.dart';
import '../../util/format.dart';
import '../scope.dart';

/// Four numbers that say how a session is going: how many calls, how many went
/// wrong, how long they take on average, and how much they moved. The statistics
/// page has the rest.
class MetricStrip extends StatelessWidget {
  /// Creates the strip for [calls].
  const MetricStrip({super.key, required this.calls});

  /// The calls the numbers are about.
  final List<FlutwireCall> calls;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final stats = SessionStats.of(calls, slowest: 0);
    final failed = stats.failed;
    final average = stats.average;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
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
        ],
      ),
    );
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.label(size: 9.5)),
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
      ),
    );
  }
}
