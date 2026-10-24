import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';
import 'package:flutwire/src/ui/stats/statistics_page.dart';

import 'calls.dart';
import 'fake_session.dart';

List<FlutwireCall> _sample() => [
  makeCall(
    4,
    method: 'POST',
    url: 'https://api.test/login',
    status: 401,
    millis: 90,
    responseBody: '{"error":"bad password"}',
  ),
  makeCall(3, url: 'https://api.test/items/9', millis: 3400),
  makeCall(
    2,
    method: 'DELETE',
    url: 'https://cdn.test/files/7',
    status: 500,
    millis: 300,
  ),
  makeCall(
    1,
    url: 'https://api.test/boom',
    status: null,
    state: FlutwireCallState.failed,
    error: const FlutwireError(type: 'SocketException', message: 'no route'),
  ),
];

Future<FakeSession> open(
  WidgetTester tester, {
  List<FlutwireCall>? calls,
  Size size = const Size(420, 1400),
  FlutwireConfig config = quietConfig,
}) async {
  setScreen(tester, size);
  final session = FakeSession(config: config, calls: calls ?? _sample());
  await tester.pumpWidget(inspectorApp(session, const StatisticsPage()));
  await settle(tester);
  return session;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

/// Where the last text with this content is. A host is named by every call to
/// it in the slowest list, and then once more in the list of hosts, which
/// comes last.
double _lastTop(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).last).dy;

void main() {
  group('the summary', () {
    testWidgets('gives the numbers of the session', (tester) async {
      await open(tester);

      expect(find.text('Statistics'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // 401, 500 and the one that never got an answer.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('24 B'), findsOneWidget);
      expect(find.text('977 ms'), findsOneWidget);
    });

    testWidgets('gives the median and the 95th percentile', (tester) async {
      await open(tester);

      // The median tile and the row of the call that took that long.
      expect(find.text('120 ms'), findsNWidgets(2));
      // The 95th percentile, the slowest tile and the row of the call.
      expect(find.text('3.40 s'), findsNWidgets(3));
    });

    testWidgets('lists the slowest calls, the slowest first', (tester) async {
      await open(tester);

      expect(find.text('SLOWEST CALLS'), findsNWidgets(2));
      final order = [
        'GET  /items/9',
        'DELETE  /files/7',
        'GET  /boom',
        'POST  /login',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(
          _top(tester, order[i - 1]),
          lessThan(_top(tester, order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
    });

    testWidgets('ranks the hosts that fail most first', (tester) async {
      await open(tester);

      expect(find.text('ERROR RATE BY HOST'), findsOneWidget);
      expect(
        _lastTop(tester, 'cdn.test'),
        lessThan(_lastTop(tester, 'api.test')),
      );
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('67%'), findsOneWidget);
      expect(find.textContaining('1 call, 1 failed'), findsOneWidget);
      expect(find.textContaining('3 calls, 2 failed'), findsOneWidget);
    });

    testWidgets('opens a call from the slowest list', (tester) async {
      await open(tester);

      await tester.tap(find.text('GET  /items/9'));
      await settle(tester);

      expect(find.byType(CallDetailPage), findsOneWidget);
      expect(find.text('https://api.test/items/9'), findsOneWidget);
    });

    testWidgets('keeps a conversation out of the times', (tester) async {
      final socket = makeCall(5, url: 'https://api.test/socket', millis: 600000)
          .copyWith(
            messages: const FlutwireMessages(
              kind: FlutwireConversationKind.webSocket,
              items: [],
              total: 0,
              keptBytes: 0,
            ),
          );

      await open(tester, calls: [socket, makeCall(1, millis: 100)]);

      expect(find.text('10.0 min'), findsNothing);
      expect(find.textContaining('min'), findsNothing);
      // The median and the slowest are the one call that has a latency.
      expect(find.text('100 ms'), findsNWidgets(5));
    });

    testWidgets('follows the history as calls arrive', (tester) async {
      final session = await open(tester);
      expect(find.text('4'), findsOneWidget);

      session.store.put(makeCall(9, url: 'https://new.test/x', status: 503));
      session.store.flush();
      await settle(tester, 800);

      expect(find.text('5'), findsOneWidget);
      // In the slowest list, and once more among the hosts.
      expect(find.text('new.test'), findsNWidgets(2));
    });

    testWidgets('says so when nothing was recorded', (tester) async {
      await open(tester, calls: const []);

      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(find.text('Summary'), findsNothing);
    });
  });

  group('the timeline', () {
    Future<void> toTimeline(WidgetTester tester) async {
      await tester.tap(find.text('Timeline'));
      await settle(tester);
    }

    testWidgets('draws every call on one row', (tester) async {
      await open(tester);

      await toTimeline(tester);

      for (final label in [
        'POST  /login',
        'GET  /items/9',
        'DELETE  /files/7',
        'GET  /boom',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('Receiving'), findsOneWidget);
    });

    testWidgets('says how many calls were in flight at once', (tester) async {
      await open(tester);

      await toTimeline(tester);

      // The calls of the sample all began at the same moment.
      expect(find.text('Up to 4 at once'), findsOneWidget);
    });

    testWidgets('says so for calls that came one after the other', (
      tester,
    ) async {
      final start = DateTime.utc(2026, 10, 24, 9);
      FlutwireCall at(int id, int seconds) {
        final call = makeCall(id, millis: 100);
        return FlutwireCall(
          id: id,
          method: call.method,
          uri: call.uri,
          source: call.source,
          state: call.state,
          startedAt: start.add(Duration(seconds: seconds)),
          endedAt: start.add(Duration(seconds: seconds, milliseconds: 100)),
          request: call.request,
          response: call.response,
        );
      }

      await open(tester, calls: [at(2, 5), at(1, 0)]);
      await toTimeline(tester);

      expect(find.text('One at a time'), findsOneWidget);
    });

    testWidgets('holds the latest hundred calls and says so', (tester) async {
      await open(
        tester,
        calls: [for (var i = 120; i >= 1; i--) makeCall(i, millis: 10)],
      );

      await toTimeline(tester);

      expect(find.text('The latest 100 of 120 calls'), findsOneWidget);
    });

    testWidgets('opens a call from its row', (tester) async {
      await open(tester);
      await toTimeline(tester);

      await tester.tap(find.text('POST  /login'));
      await settle(tester);

      expect(find.byType(CallDetailPage), findsOneWidget);
    });
  });

  testWidgets('reads in Italian', (tester) async {
    await open(
      tester,
      config: const FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: Locale('it'),
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    );

    expect(find.text('Statistiche'), findsOneWidget);
    expect(find.text('Riepilogo'), findsOneWidget);
    expect(find.text('CHIAMATE PIÙ LENTE'), findsNWidgets(2));
    expect(find.text('ERRORI PER HOST'), findsOneWidget);
    expect(find.textContaining('1 chiamata, 1 fallita'), findsOneWidget);

    await tester.tap(find.text('Linea del tempo'));
    await settle(tester);
    expect(find.text('Fino a 4 insieme'), findsOneWidget);
  });
}
