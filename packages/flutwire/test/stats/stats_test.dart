import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/stats/stats.dart';

final _start = DateTime.utc(2026, 10, 24, 12);

FlutwireCall _call(
  int id, {
  String host = 'api.test',
  int? status = 200,
  FlutwireCallState? state,
  int millis = 100,
  int atMillis = 0,
  int? firstByteMillis,
  int requestBytes = 0,
  int responseBytes = 0,
  bool conversation = false,
  FlutwireIntercept? intercept,
}) {
  final pending = state == FlutwireCallState.pending;
  final begun = _start.add(Duration(milliseconds: atMillis));
  return FlutwireCall(
    id: id,
    method: 'GET',
    uri: Uri.parse('https://$host/items/$id'),
    source: FlutwireSource.io,
    state:
        state ??
        (status == null
            ? FlutwireCallState.failed
            : FlutwireCallState.completed),
    startedAt: begun,
    firstByteAt: firstByteMillis == null
        ? null
        : begun.add(Duration(milliseconds: firstByteMillis)),
    endedAt: pending ? null : begun.add(Duration(milliseconds: millis)),
    request: FlutwireRequest(
      headers: FlutwireHeaders.empty,
      body: FlutwireBody.unloaded(totalBytes: requestBytes),
    ),
    response: status == null
        ? null
        : FlutwireResponse(
            statusCode: status,
            headers: FlutwireHeaders.empty,
            body: FlutwireBody.unloaded(totalBytes: responseBytes),
          ),
    messages: conversation
        ? const FlutwireMessages(
            kind: FlutwireConversationKind.webSocket,
            items: [],
            total: 0,
            keptBytes: 0,
          )
        : null,
    intercept: intercept,
  );
}

void main() {
  group('SessionStats', () {
    test('has nothing to say about an empty history', () {
      final stats = SessionStats.of(const []);

      expect(stats.total, 0);
      expect(stats.failed, 0);
      expect(stats.errorRate, 0);
      expect(stats.average, isNull);
      expect(stats.median, isNull);
      expect(stats.p95, isNull);
      expect(stats.slowest, isEmpty);
      expect(stats.hosts, isEmpty);
      expect(stats.bytesTransferred, 0);
    });

    test('counts what failed and what moved', () {
      final stats = SessionStats.of([
        _call(1, requestBytes: 10, responseBytes: 100),
        _call(2, status: 404, responseBytes: 5),
        _call(3, status: 500),
        _call(4, status: null),
      ]);

      expect(stats.total, 4);
      expect(stats.failed, 3);
      expect(stats.errorRate, 0.75);
      expect(stats.bytesSent, 10);
      expect(stats.bytesReceived, 105);
      expect(stats.bytesTransferred, 115);
    });

    test('does not judge a call that is still waiting', () {
      final stats = SessionStats.of([
        _call(1),
        _call(2, status: null, state: FlutwireCallState.pending),
        _call(3, status: 500, state: FlutwireCallState.pending),
      ]);

      // The one with no answer yet is neither right nor wrong.
      expect(stats.decided, 2);
      expect(stats.failed, 1);
      expect(stats.errorRate, 0.5);
    });

    test('reads the times of the calls that ended', () {
      final stats = SessionStats.of([
        for (var i = 1; i <= 10; i++) _call(i, millis: i * 10),
        _call(11, status: null, state: FlutwireCallState.pending),
      ]);

      expect(stats.average, const Duration(milliseconds: 55));
      expect(stats.median, const Duration(milliseconds: 50));
      expect(stats.p95, const Duration(milliseconds: 100));
    });

    test('keeps a conversation out of the times and in the counts', () {
      final stats = SessionStats.of([
        _call(1, millis: 100),
        _call(2, millis: 900000, conversation: true),
        _call(3, status: 500, millis: 800000, conversation: true),
      ]);

      expect(stats.total, 3);
      expect(stats.failed, 1);
      expect(stats.average, const Duration(milliseconds: 100));
      expect(stats.slowest.map((c) => c.id), [1]);
    });

    test('keeps a call that was held at a breakpoint out of the times', () {
      final stats = SessionStats.of([
        _call(1, millis: 100),
        _call(
          2,
          status: null,
          millis: 70000,
          intercept: FlutwireIntercept.held,
        ),
        _call(3, millis: 300, intercept: FlutwireIntercept.edited),
      ]);

      // The one that was held still counts as a call, and it failed.
      expect(stats.total, 3);
      expect(stats.failed, 1);
      expect(stats.average, const Duration(milliseconds: 200));
      expect(stats.slowest.map((c) => c.id), [3, 1]);
      expect(stats.hosts.single.average, const Duration(milliseconds: 200));
    });

    test('lists the slowest first, and no more than asked for', () {
      final stats = SessionStats.of([
        _call(1, millis: 50),
        _call(2, millis: 300),
        _call(3, millis: 200),
        _call(4, millis: 400),
      ], slowest: 3);

      expect(stats.slowest.map((c) => c.id), [4, 2, 3]);
    });

    test('ranks the hosts that fail most first', () {
      final stats = SessionStats.of([
        _call(1, host: 'a.test'),
        _call(2, host: 'a.test'),
        _call(3, host: 'a.test'),
        _call(4, host: 'a.test', status: 500),
        _call(5, host: 'b.test', status: 500),
        _call(6, host: 'b.test', status: null),
        for (var i = 7; i < 17; i++) _call(i, host: 'c.test'),
      ]);

      expect(stats.hosts.map((h) => h.host), ['b.test', 'a.test', 'c.test']);
      final b = stats.hosts.first;
      expect(b.calls, 2);
      expect(b.failed, 2);
      expect(b.errorRate, 1);
      expect(stats.hosts[1].errorRate, 0.25);
      expect(stats.hosts.last.errorRate, 0);
    });

    test('breaks a tie between hosts the same way every time', () {
      final stats = SessionStats.of([
        _call(1, host: 'b.test'),
        _call(2, host: 'a.test'),
        _call(3, host: 'a.test'),
      ]);

      // Neither fails: the one with more calls comes first.
      expect(stats.hosts.map((h) => h.host), ['a.test', 'b.test']);
    });

    test('gives a host the mean time of its own calls', () {
      final stats = SessionStats.of([
        _call(1, host: 'a.test', millis: 100),
        _call(2, host: 'a.test', millis: 300),
        _call(
          3,
          host: 'b.test',
          status: null,
          state: FlutwireCallState.pending,
        ),
      ]);

      final a = stats.hosts.firstWhere((h) => h.host == 'a.test');
      final b = stats.hosts.firstWhere((h) => h.host == 'b.test');
      expect(a.average, const Duration(milliseconds: 200));
      expect(b.average, isNull);
    });
  });

  group('Waterfall', () {
    final now = _start.add(const Duration(seconds: 10));

    test('puts the calls in the order they began, from the first', () {
      final waterfall = Waterfall.of([
        _call(2, atMillis: 500, millis: 100),
        _call(1, atMillis: 200, millis: 300, firstByteMillis: 120),
      ], now: now);

      expect(waterfall.rows.map((r) => r.call.id), [1, 2]);
      expect(waterfall.rows[0].offset, Duration.zero);
      expect(waterfall.rows[0].length, const Duration(milliseconds: 300));
      expect(waterfall.rows[0].waiting, const Duration(milliseconds: 120));
      expect(waterfall.rows[1].offset, const Duration(milliseconds: 300));
      expect(waterfall.rows[1].waiting, isNull);
      expect(waterfall.span, const Duration(milliseconds: 400));
    });

    test('keeps the latest calls and says how many there are', () {
      final waterfall = Waterfall.of(
        [for (var i = 1; i <= 8; i++) _call(i, atMillis: i * 100)],
        now: now,
        limit: 5,
      );

      expect(waterfall.rows.map((r) => r.call.id), [4, 5, 6, 7, 8]);
      expect(waterfall.total, 8);
      expect(waterfall.isCut, isTrue);
      expect(waterfall.rows.first.offset, Duration.zero);
    });

    test('leaves out what came before the latest long pause', () {
      final waterfall = Waterfall.of([
        _call(1, atMillis: 0),
        _call(2, atMillis: 500),
        _call(3, atMillis: 600000),
        _call(4, atMillis: 600200),
      ], now: _start.add(const Duration(minutes: 11)));

      expect(waterfall.rows.map((r) => r.call.id), [3, 4]);
      expect(waterfall.total, 4);
      expect(waterfall.isCut, isTrue);
      expect(waterfall.rows.first.offset, Duration.zero);
      expect(waterfall.span, const Duration(milliseconds: 300));
    });

    test('keeps a call that was still running through the pause', () {
      final waterfall = Waterfall.of([
        _call(1, atMillis: 0, millis: 700000),
        _call(2, atMillis: 600000),
      ], now: _start.add(const Duration(minutes: 12)));

      expect(waterfall.rows.map((r) => r.call.id), [1, 2]);
      expect(waterfall.isCut, isFalse);
    });

    test('takes a pause to be as long as it was told', () {
      final calls = [_call(1, atMillis: 0), _call(2, atMillis: 5000)];
      final at = _start.add(const Duration(seconds: 10));

      expect(
        Waterfall.of(
          calls,
          now: at,
          lull: const Duration(seconds: 3),
        ).rows.map((r) => r.call.id),
        [2],
      );
      expect(
        Waterfall.of(
          calls,
          now: at,
          lull: const Duration(seconds: 10),
        ).rows.map((r) => r.call.id),
        [1, 2],
      );
    });

    test('draws a call that has not ended as lasting until now', () {
      final waterfall = Waterfall.of([
        _call(1, atMillis: 0, millis: 100),
        _call(
          2,
          atMillis: 1000,
          status: null,
          state: FlutwireCallState.pending,
        ),
      ], now: now);

      expect(waterfall.rows.last.length, const Duration(seconds: 9));
      expect(waterfall.span, const Duration(seconds: 10));
    });

    test('counts the most calls that were in flight together', () {
      final waterfall = Waterfall.of([
        _call(1, atMillis: 0, millis: 500),
        _call(2, atMillis: 100, millis: 500),
        _call(3, atMillis: 200, millis: 100),
        _call(4, atMillis: 900, millis: 100),
      ], now: now);

      expect(waterfall.peak, 3);
    });

    test('does not count a call that ends as another one begins', () {
      final waterfall = Waterfall.of([
        _call(1, atMillis: 0, millis: 100),
        _call(2, atMillis: 100, millis: 100),
      ], now: now);

      expect(waterfall.peak, 1);
    });

    test('counts a call that took no time', () {
      final waterfall = Waterfall.of([_call(1, millis: 0)], now: now);

      expect(waterfall.peak, 1);
    });

    test('is empty for no calls', () {
      final waterfall = Waterfall.of(const [], now: now);

      expect(waterfall.rows, isEmpty);
      expect(waterfall.span, Duration.zero);
      expect(waterfall.peak, 0);
      expect(waterfall.isCut, isFalse);
    });
  });

  group('timeTicks', () {
    test('has the start alone for a span of nothing', () {
      expect(timeTicks(Duration.zero), [Duration.zero]);
    });

    test('marks round numbers up to the span', () {
      for (final span in const [
        Duration(milliseconds: 1),
        Duration(milliseconds: 37),
        Duration(milliseconds: 400),
        Duration(seconds: 1),
        Duration(milliseconds: 2500),
        Duration(seconds: 61),
        Duration(hours: 3),
      ]) {
        final ticks = timeTicks(span);

        expect(ticks.first, Duration.zero, reason: '$span');
        expect(ticks.last, lessThanOrEqualTo(span), reason: '$span');
        expect(ticks.length, inInclusiveRange(2, 9), reason: '$span');
        final step = ticks[1].inMicroseconds;
        expect(
          [1, 2, 5].contains(_leadingDigit(step)) &&
              step == _leadingDigit(step) * _powerOfTen(step),
          isTrue,
          reason: '$span steps by $step µs',
        );
        for (var i = 1; i < ticks.length; i++) {
          expect(ticks[i].inMicroseconds - ticks[i - 1].inMicroseconds, step);
        }
      }
    });
  });
}

int _powerOfTen(int n) {
  var power = 1;
  while (power * 10 <= n) {
    power *= 10;
  }
  return power;
}

int _leadingDigit(int n) => n ~/ _powerOfTen(n);
