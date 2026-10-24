import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/l10n/strings_it.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';
import 'package:flutwire/src/ui/detail/messages_tab.dart';
import 'package:flutwire/src/ui/widgets/call_tile.dart';

import 'calls.dart';
import 'fake_session.dart';
import 'harness.dart';

final start = DateTime.utc(2026, 10, 23, 12);

FlutwireMessage message(
  int index, {
  bool sent = false,
  FlutwireMessageKind kind = FlutwireMessageKind.text,
  String? text,
  List<int>? bytes,
  int? total,
  String? event,
  int millis = 0,
}) {
  final payload = bytes ?? utf8.encode(text ?? 'message $index');
  return FlutwireMessage(
    index: index,
    sent: sent,
    at: start.add(Duration(milliseconds: millis)),
    kind: kind,
    bytes: Uint8List.fromList(payload),
    totalBytes: total ?? payload.length,
    event: event,
  );
}

FlutwireCall conversation(
  List<FlutwireMessage> items, {
  FlutwireConversationKind kind = FlutwireConversationKind.webSocket,
  FlutwireCallState state = FlutwireCallState.completed,
  int? total,
  int id = 1,
}) => makeCall(id, status: 101, state: state).copyWith(
  messages: FlutwireMessages(
    kind: kind,
    items: items,
    total: total ?? items.length,
    keptBytes: items.fold(0, (sum, m) => sum + m.bytes.length),
  ),
);

void main() {
  group('the tab', () {
    Future<void> open(WidgetTester tester, FlutwireCall call) async {
      setScreen(tester, const Size(420, 900));
      final session = FakeSession(calls: [call]);
      await tester.pumpWidget(
        inspectorApp(session, CallDetailPage(callId: call.id)),
      );
      await settle(tester);
    }

    testWidgets('is there for a WebSocket and is called Messages', (
      tester,
    ) async {
      await open(tester, conversation([message(0)]));

      // Once as the tab, and once as the line of the overview.
      expect(find.text('Messages'), findsNWidgets(2));
    });

    testWidgets('is called Events for an event stream', (tester) async {
      await open(
        tester,
        conversation([
          message(0, kind: FlutwireMessageKind.event),
        ], kind: FlutwireConversationKind.eventStream),
      );

      expect(find.text('Events'), findsNWidgets(2));
      expect(find.text('Messages'), findsNothing);
    });

    testWidgets('is not there for an ordinary call', (tester) async {
      await open(tester, makeCall(1));

      expect(find.text('Messages'), findsNothing);
      expect(find.text('Events'), findsNothing);
    });

    testWidgets('opens on the list of messages', (tester) async {
      await open(tester, conversation([message(0, text: 'hello')]));

      await tester.tap(find.text('Messages').first);
      await settle(tester);

      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('is counted in the overview too', (tester) async {
      await open(tester, conversation([message(0), message(1)]));

      expect(find.text('2 messages'), findsWidgets);
    });
  });

  group('the messages', () {
    Future<void> show(
      WidgetTester tester,
      FlutwireCall call, {
      FakeSession? session,
    }) async {
      await pumpFlutwire(
        tester,
        MessagesTab(call: call),
        session: session,
        size: const Size(420, 900),
      );
      await settle(tester);
    }

    testWidgets('say which way they went, what they are and how big', (
      tester,
    ) async {
      await show(
        tester,
        conversation([
          message(0, sent: true, text: 'hello'),
          message(1, text: 'world!', millis: 1500),
        ]),
      );

      expect(find.text('Text  ·  5 B'), findsOneWidget);
      expect(find.text('Text  ·  6 B'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world!'), findsOneWidget);
      expect(find.text('+1.50 s'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('keep a long text to a line or two', (tester) async {
      await show(tester, conversation([message(0, text: 'word ' * 200)]));

      final preview = tester.widget<Text>(find.textContaining('word word'));
      expect(preview.maxLines, 2);
      expect(preview.data!.length, lessThan(300));
    });

    testWidgets('show the first bytes of a binary one', (tester) async {
      await show(
        tester,
        conversation([
          message(0, kind: FlutwireMessageKind.binary, bytes: [0, 255, 16, 1]),
        ]),
      );

      expect(find.text('Binary  ·  4 B'), findsOneWidget);
      expect(find.text('00 ff 10 01'), findsOneWidget);
    });

    testWidgets('show how a binary one goes on past the first bytes', (
      tester,
    ) async {
      await show(
        tester,
        conversation([
          message(
            0,
            kind: FlutwireMessageKind.binary,
            bytes: List.generate(16, (i) => i),
            total: 5000,
          ),
        ]),
      );

      expect(find.textContaining('0f …'), findsOneWidget);
    });

    testWidgets('show the code and the reason of a close', (tester) async {
      await show(
        tester,
        conversation([
          message(
            0,
            kind: FlutwireMessageKind.close,
            bytes: [0x03, 0xe8, ...utf8.encode('done')],
          ),
        ]),
      );

      expect(find.text('Close  ·  6 B'), findsOneWidget);
      expect(find.text('1000 done'), findsOneWidget);
    });

    testWidgets('show nothing under a ping that carries nothing', (
      tester,
    ) async {
      await show(
        tester,
        conversation([
          message(0, sent: true, kind: FlutwireMessageKind.ping, bytes: []),
        ]),
      );

      expect(find.text('Ping  ·  0 B'), findsOneWidget);
    });

    testWidgets('are told apart by direction', (tester) async {
      await show(
        tester,
        conversation([
          message(0, sent: true, text: 'from the app'),
          message(1, text: 'from the server'),
        ]),
      );

      await tester.tap(find.text('Sent'));
      await settle(tester);

      expect(find.text('from the app'), findsOneWidget);
      expect(find.text('from the server'), findsNothing);

      await tester.tap(find.text('Received'));
      await settle(tester);

      expect(find.text('from the app'), findsNothing);
      expect(find.text('from the server'), findsOneWidget);

      await tester.tap(find.text('All'));
      await settle(tester);

      expect(find.text('from the app'), findsOneWidget);
      expect(find.text('from the server'), findsOneWidget);
    });

    testWidgets('say when there is nothing yet', (tester) async {
      await show(tester, conversation(const []));

      expect(find.text('Nothing has crossed yet'), findsOneWidget);
      expect(find.text('0 messages'), findsOneWidget);
    });

    testWidgets('say how many at the start were not kept', (tester) async {
      await show(
        tester,
        conversation([message(200), message(201)], total: 202),
      );

      expect(find.text('202 messages'), findsOneWidget);
      expect(find.text('200 earlier messages were not kept.'), findsOneWidget);
    });

    testWidgets('of an event stream have a name, and no direction to pick', (
      tester,
    ) async {
      await show(
        tester,
        conversation([
          message(0, kind: FlutwireMessageKind.event, event: 'tick'),
          message(1, kind: FlutwireMessageKind.event, text: '{"n":2}'),
        ], kind: FlutwireConversationKind.eventStream),
      );

      expect(find.text('tick  ·  9 B'), findsOneWidget);
      expect(find.text('Event  ·  7 B'), findsOneWidget);
      expect(find.text('2 events'), findsOneWidget);
      expect(find.text('Sent'), findsNothing);
    });

    testWidgets('open in a sheet with the payload in the viewer', (
      tester,
    ) async {
      await show(tester, conversation([message(0, text: '{"price":42}')]));

      await tester.tap(find.text('{"price":42}'));
      await settle(tester);

      expect(find.text('Received  ·  Text  ·  12 B'), findsOneWidget);
      expect(find.textContaining('price'), findsWidgets);
    });

    testWidgets('one that could not be decompressed says so', (tester) async {
      await show(
        tester,
        conversation([
          FlutwireMessage(
            index: 0,
            sent: false,
            at: start,
            kind: FlutwireMessageKind.binary,
            bytes: Uint8List.fromList([1, 2, 3, 4]),
            totalBytes: 4,
            undecoded: true,
          ),
        ]),
      );

      await tester.tap(find.text('01 02 03 04'));
      await settle(tester);

      expect(find.textContaining('could not be decompressed'), findsOneWidget);
    });

    testWidgets('a close opens as its code and reason', (tester) async {
      await show(
        tester,
        conversation([
          message(
            0,
            kind: FlutwireMessageKind.close,
            bytes: [0x03, 0xe9, ...utf8.encode('going away')],
          ),
        ]),
      );

      await tester.tap(find.text('1001 going away'));
      await settle(tester);

      expect(find.text('Received  ·  Close  ·  12 B'), findsOneWidget);
      expect(find.text('1001 going away'), findsWidgets);
    });

    testWidgets('speak Italian when the app does', (tester) async {
      await pumpFlutwire(
        tester,
        MessagesTab(call: conversation([message(0, sent: true), message(1)])),
        strings: const FlutwireStringsIt(),
        size: const Size(420, 900),
      );
      await settle(tester);

      expect(find.text('2 messaggi'), findsOneWidget);
      expect(find.text('Tutti'), findsOneWidget);
      expect(find.text('Inviati'), findsOneWidget);
      expect(find.text('Ricevuti'), findsOneWidget);
      expect(find.text('Testo  ·  9 B'), findsNWidgets(2));
    });
  });

  testWidgets('a conversation is badged in the list', (tester) async {
    final now = DateTime.utc(2026, 10, 23, 12, 1);
    await pumpFlutwire(
      tester,
      Column(
        children: [
          CallTile(call: conversation([message(0)]), now: now),
          CallTile(
            call: conversation(
              [message(0, kind: FlutwireMessageKind.event)],
              kind: FlutwireConversationKind.eventStream,
              id: 2,
            ),
            now: now,
          ),
          CallTile(call: makeCall(3), now: now),
        ],
      ),
    );

    expect(find.text('WS'), findsOneWidget);
    expect(find.text('SSE'), findsOneWidget);
  });

  group('while the call runs', () {
    Future<ValueNotifier<FlutwireCall>> follow(
      WidgetTester tester,
      int count,
    ) async {
      final notifier = ValueNotifier(
        conversation([
          for (var i = 0; i < count; i++) message(i),
        ], state: FlutwireCallState.pending),
      );
      await pumpFlutwire(
        tester,
        ValueListenableBuilder<FlutwireCall>(
          valueListenable: notifier,
          builder: (_, call, _) => MessagesTab(call: call),
        ),
        size: const Size(420, 900),
      );
      await settle(tester);
      return notifier;
    }

    double offset(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

    double end(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .maxScrollExtent;

    FlutwireCall grown(int count) => conversation([
      for (var i = 0; i < count; i++) message(i),
    ], state: FlutwireCallState.pending);

    testWidgets('the list opens on the newest message', (tester) async {
      await follow(tester, 60);

      expect(end(tester), greaterThan(0));
      expect(offset(tester), end(tester));
    });

    testWidgets('and keeps following as more arrive', (tester) async {
      final notifier = await follow(tester, 60);

      notifier.value = grown(70);
      await settle(tester);

      expect(offset(tester), end(tester));
    });

    testWidgets('until the reader scrolls up to an older one', (tester) async {
      final notifier = await follow(tester, 60);

      await tester.drag(find.byType(Scrollable), const Offset(0, 400));
      await settle(tester);
      final where = offset(tester);
      notifier.value = grown(70);
      await settle(tester);

      expect(offset(tester), where);
      expect(offset(tester), lessThan(end(tester)));
    });

    testWidgets('and follows again once the reader is back at the end', (
      tester,
    ) async {
      final notifier = await follow(tester, 60);

      await tester.drag(find.byType(Scrollable), const Offset(0, 400));
      await settle(tester);
      await tester.drag(find.byType(Scrollable), const Offset(0, -2000));
      await settle(tester);
      notifier.value = grown(70);
      await settle(tester);

      expect(offset(tester), end(tester));
    });

    testWidgets('a finished call opens at the first message', (tester) async {
      await pumpFlutwire(
        tester,
        MessagesTab(
          call: conversation([for (var i = 0; i < 60; i++) message(i)]),
        ),
        size: const Size(420, 900),
      );
      await settle(tester);

      expect(offset(tester), 0);
    });
  });
}
