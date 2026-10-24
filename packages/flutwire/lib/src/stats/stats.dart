import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import '../model/call.dart';

/// What a history says about itself: how many calls went wrong, how long they
/// take, which are the slowest and which hosts fail most.
///
/// A WebSocket or an event stream stays open for as long as it has something to
/// say, so how long it lasts says nothing about latency. It counts as a call,
/// and a failed one counts as a failure, but it takes no part in the times.
@immutable
final class SessionStats {
  const SessionStats._({
    required this.total,
    required this.failed,
    required this.decided,
    required this.bytesSent,
    required this.bytesReceived,
    required this.average,
    required this.median,
    required this.p95,
    required this.slowest,
    required this.hosts,
  });

  /// Works out the numbers for [calls]. [slowest] is how many of the slowest
  /// calls to keep.
  factory SessionStats.of(Iterable<FlutwireCall> calls, {int slowest = 10}) {
    var total = 0;
    var failed = 0;
    var decided = 0;
    var sent = 0;
    var received = 0;
    final timed = <FlutwireCall>[];
    final byHost = <String, _HostTally>{};
    for (final call in calls) {
      total++;
      sent += call.requestSize;
      received += call.responseSize;
      final judged = _isJudged(call);
      if (judged) decided++;
      if (call.isError) failed++;
      final isTimed = !call.isPending && call.messages == null;
      if (isTimed) timed.add(call);
      final tally = byHost.putIfAbsent(call.host, _HostTally.new);
      tally.calls++;
      tally.bytes += call.requestSize + call.responseSize;
      if (judged) tally.decided++;
      if (call.isError) tally.failed++;
      if (isTimed) {
        tally.timed++;
        tally.micros += call.duration.inMicroseconds;
      }
    }
    final durations = [for (final call in timed) call.duration.inMicroseconds]
      ..sort();
    final slowestFirst = [...timed]
      ..sort((a, b) => b.duration.compareTo(a.duration));
    final hosts = [
      for (final entry in byHost.entries)
        HostStats._(
          host: entry.key,
          calls: entry.value.calls,
          failed: entry.value.failed,
          decided: entry.value.decided,
          bytes: entry.value.bytes,
          average: entry.value.timed == 0
              ? null
              : Duration(microseconds: entry.value.micros ~/ entry.value.timed),
        ),
    ]..sort(HostStats._worstFirst);
    return SessionStats._(
      total: total,
      failed: failed,
      decided: decided,
      bytesSent: sent,
      bytesReceived: received,
      average: durations.isEmpty
          ? null
          : Duration(
              microseconds:
                  durations.fold<int>(0, (sum, d) => sum + d) ~/
                  durations.length,
            ),
      median: _percentile(durations, 0.5),
      p95: _percentile(durations, 0.95),
      slowest: slowestFirst.take(slowest).toList(),
      hosts: hosts,
    );
  }

  /// How many calls there are.
  final int total;

  /// How many failed or got an error status.
  final int failed;

  /// How many calls have been judged: those that have ended, and those that
  /// already failed. A call still waiting for its answer is neither a success
  /// nor a failure yet.
  final int decided;

  /// The bytes the app sent in bodies.
  final int bytesSent;

  /// The bytes the app received in bodies.
  final int bytesReceived;

  /// The mean time of the calls that ended, or null when none has.
  final Duration? average;

  /// The time half of the calls that ended came in under.
  final Duration? median;

  /// The time nineteen calls in twenty came in under.
  final Duration? p95;

  /// The slowest calls that ended, the slowest first.
  final List<FlutwireCall> slowest;

  /// The hosts, the ones that fail most first.
  final List<HostStats> hosts;

  /// The share of judged calls that went wrong, from 0 to 1.
  double get errorRate => decided == 0 ? 0 : failed / decided;

  /// The bytes that moved either way.
  int get bytesTransferred => bytesSent + bytesReceived;

  static bool _isJudged(FlutwireCall call) => !call.isPending || call.isError;

  /// The value at [fraction] of the way up [sorted], by the nearest rank.
  static Duration? _percentile(List<int> sorted, double fraction) {
    if (sorted.isEmpty) return null;
    final rank = (fraction * sorted.length).ceil().clamp(1, sorted.length);
    return Duration(microseconds: sorted[rank - 1]);
  }
}

class _HostTally {
  int calls = 0;
  int failed = 0;
  int decided = 0;
  int timed = 0;
  int micros = 0;
  int bytes = 0;
}

/// How the calls to one host went.
@immutable
final class HostStats {
  const HostStats._({
    required this.host,
    required this.calls,
    required this.failed,
    required this.decided,
    required this.bytes,
    required this.average,
  });

  /// The host, which is empty for an address that has none.
  final String host;

  /// How many calls went to it.
  final int calls;

  /// How many of them failed or got an error status.
  final int failed;

  /// How many of them have been judged.
  final int decided;

  /// The bytes that moved either way.
  final int bytes;

  /// The mean time of its calls that ended, or null when none has.
  final Duration? average;

  /// The share of its judged calls that went wrong, from 0 to 1.
  double get errorRate => decided == 0 ? 0 : failed / decided;

  /// The worst first: the highest error rate, then the most failures, then the
  /// most calls, then the name, so that the order never wobbles.
  static int _worstFirst(HostStats a, HostStats b) {
    final byRate = b.errorRate.compareTo(a.errorRate);
    if (byRate != 0) return byRate;
    final byFailures = b.failed.compareTo(a.failed);
    if (byFailures != 0) return byFailures;
    final byCalls = b.calls.compareTo(a.calls);
    return byCalls != 0 ? byCalls : a.host.compareTo(b.host);
  }
}

/// One call in a timeline: when it began, how long it waited and how long it
/// lasted.
@immutable
final class WaterfallRow {
  /// Creates a row.
  const WaterfallRow({
    required this.call,
    required this.offset,
    required this.length,
    this.waiting,
  });

  /// The call.
  final FlutwireCall call;

  /// How long after the start of the timeline the call began.
  final Duration offset;

  /// How long the call lasted, or has lasted so far.
  final Duration length;

  /// How long the call waited for the first byte of the answer, or null when
  /// none came.
  final Duration? waiting;

  /// When the call ended, counted from the start of the timeline.
  Duration get end => offset + length;
}

/// The latest calls laid out on one time line, so that calls that overlapped
/// can be seen to.
@immutable
final class Waterfall {
  const Waterfall._({
    required this.rows,
    required this.total,
    required this.span,
    required this.peak,
  });

  /// Lays out the latest [limit] of [calls]. A call that has not ended is
  /// drawn as lasting until [now].
  factory Waterfall.of(
    Iterable<FlutwireCall> calls, {
    required DateTime now,
    int limit = 100,
  }) {
    final all = calls.toList();
    final latest = [...all]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final shown = latest.length > limit
        ? latest.sublist(latest.length - limit)
        : latest;
    if (shown.isEmpty) {
      return Waterfall._(
        rows: const [],
        total: all.length,
        span: Duration.zero,
        peak: 0,
      );
    }
    final origin = shown.first.startedAt;
    final rows = [
      for (final call in shown)
        WaterfallRow(
          call: call,
          offset: call.startedAt.difference(origin),
          length: _lasted(call, now),
          waiting: call.timeToFirstByte,
        ),
    ];
    final span = rows.fold<Duration>(
      Duration.zero,
      (longest, row) => row.end > longest ? row.end : longest,
    );
    return Waterfall._(
      rows: rows,
      total: all.length,
      span: span,
      peak: _peak(rows),
    );
  }

  /// The calls, the earliest first.
  final List<WaterfallRow> rows;

  /// How many calls there are, shown or not.
  final int total;

  /// How long the timeline is, from the start of the first call to the end of
  /// the last one.
  final Duration span;

  /// The most calls that were in flight at once.
  final int peak;

  /// Whether some of the calls are not in the timeline.
  bool get isCut => rows.length < total;

  static Duration _lasted(FlutwireCall call, DateTime now) {
    final end = call.endedAt ?? now;
    final lasted = end.difference(call.startedAt);
    return lasted.isNegative ? Duration.zero : lasted;
  }

  /// The most rows that overlap at one moment. A call that ends as another one
  /// begins does not overlap it.
  static int _peak(List<WaterfallRow> rows) {
    final moments =
        <(int, int)>[
          for (final row in rows) ...[
            (row.offset.inMicroseconds, 1),
            // A call that took no time still was in flight.
            (
              math.max(row.end.inMicroseconds, row.offset.inMicroseconds + 1),
              -1,
            ),
          ],
        ]..sort(
          (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
        );
    var open = 0;
    var peak = 0;
    for (final (_, step) in moments) {
      open += step;
      if (open > peak) peak = open;
    }
    return peak;
  }
}

/// Marks along a time line of length [span], at round numbers: a handful of
/// them, from nothing up to [span].
///
/// The distance between two marks is 1, 2 or 5 times a power of ten, whichever
/// comes closest to a fraction of [span] that makes about [aim] marks.
List<Duration> timeTicks(Duration span, {int aim = 4}) {
  if (span <= Duration.zero) return const [Duration.zero];
  final target = span.inMicroseconds / aim;
  var every = 1;
  var distance = double.infinity;
  for (var power = 1; power <= 1000000000000; power *= 10) {
    for (final multiple in const [1, 2, 5]) {
      final step = power * multiple;
      final away = (step / target > 1 ? step / target : target / step);
      if (away < distance) {
        distance = away;
        every = step;
      }
    }
  }
  return [
    for (var at = 0; at <= span.inMicroseconds; at += every)
      Duration(microseconds: at),
  ];
}
