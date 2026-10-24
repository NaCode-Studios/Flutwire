import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../stats/stats.dart';
import '../../util/format.dart';
import '../scope.dart';
import '../theme/tokens.dart';

/// The numbers of a session, its slowest calls and how often the calls to each
/// host fail.
class SummaryView extends StatelessWidget {
  /// Creates the view for [stats]. [onOpen] opens the call with an id.
  const SummaryView({super.key, required this.stats, required this.onOpen});

  /// What to show.
  final SessionStats stats;

  /// Opens a call.
  final ValueChanged<int> onOpen;

  /// How many hosts are listed. A session can talk to a great many.
  static const int hostLimit = 20;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final hosts = stats.hosts.take(hostLimit).toList();
    final slowest = stats.slowest;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _Metrics(stats: stats),
        if (slowest.isNotEmpty) ...[
          _Heading(s.statsSlowest),
          for (final call in slowest)
            _SlowRow(
              call: call,
              longest: slowest.first.duration,
              onTap: () => onOpen(call.id),
            ),
        ],
        if (hosts.isNotEmpty) ...[
          _Heading(s.statsHosts),
          for (final host in hosts) _HostRow(host: host),
          if (stats.hosts.length > hostLimit)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                s.statsMoreHosts(stats.hosts.length - hostLimit),
                style: t.body(size: 12, color: t.faint),
              ),
            ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
      child: Text(text.toUpperCase(), style: t.label(color: t.faint)),
    );
  }
}

/// The numbers, two to a row.
class _Metrics extends StatelessWidget {
  const _Metrics({required this.stats});

  final SessionStats stats;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    String time(Duration? value) => value == null ? '·' : formatDuration(value);
    final tiles = [
      (s.statCalls, '${stats.total}', null),
      (s.statFailed, '${stats.failed}', stats.failed > 0 ? t.error : null),
      (
        s.statsErrorRate,
        _percent(stats.errorRate),
        stats.failed > 0 ? t.error : null,
      ),
      (s.statTransferred, formatBytes(stats.bytesTransferred), null),
      (s.statAverage, time(stats.average), null),
      (s.statsMedian, time(stats.median), null),
      (s.statsP95, time(stats.p95), null),
      (
        s.statsSlowest,
        time(stats.slowest.isEmpty ? null : stats.slowest.first.duration),
        null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value, color) in tiles)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(
                      FlutwireTokens.radiusMd,
                    ),
                    border: Border.all(color: t.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label.toUpperCase(), style: t.label(size: 9.5)),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: t.mono(
                            size: 20,
                            weight: FontWeight.w600,
                            color: color ?? t.ink,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A share as people read it: `0%`, `3.2%`, `25%`.
String _percent(double share) {
  final percent = share * 100;
  if (percent == 0) return '0%';
  return percent >= 10 || percent == percent.roundToDouble()
      ? '${percent.round()}%'
      : '${percent.toStringAsFixed(1)}%';
}

/// One of the slowest calls, with a bar as long as it took against the
/// slowest of them.
class _SlowRow extends StatelessWidget {
  const _SlowRow({
    required this.call,
    required this.longest,
    required this.onTap,
  });

  final FlutwireCall call;
  final Duration longest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final millis = call.duration.inMilliseconds;
    final color = millis >= 3000
        ? t.error
        : millis >= 1000
        ? t.warning
        : t.copperTone;
    final share = longest.inMicroseconds == 0
        ? 0.0
        : call.duration.inMicroseconds / longest.inMicroseconds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FlutwireTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${call.method}  ${call.graphql?.operationName ?? call.pathAndQuery}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatDuration(call.duration),
                  style: t.mono(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(call.host, style: t.body(size: 11.5, color: t.muted)),
            const SizedBox(height: 6),
            _Bar(share: share, color: color),
          ],
        ),
      ),
    );
  }
}

/// How the calls to one host went.
class _HostRow extends StatelessWidget {
  const _HostRow({required this.host});

  final HostStats host;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final rate = host.errorRate;
    final average = host.average;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  host.host.isEmpty ? s.statsNoHost : host.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _percent(rate),
                style: t.mono(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: host.failed > 0 ? t.error : t.faint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              s.statsHostLine(host.calls, host.failed),
              if (average != null) formatDuration(average),
            ].join('  ·  '),
            style: t.body(size: 11.5, color: t.muted),
          ),
          const SizedBox(height: 6),
          _Bar(
            share: host.decided == 0 ? 0 : 1 - rate,
            color: t.ok,
            rest: host.failed > 0 ? t.error : null,
          ),
        ],
      ),
    );
  }
}

/// A bar filled to [share] of its length, and when it has a [rest] colour, the
/// remainder in that colour.
class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.color, this.rest});

  final double share;
  final Color color;
  final Color? rest;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final filled = share.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: ColoredBox(
          color: rest ?? t.line,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: filled,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}
