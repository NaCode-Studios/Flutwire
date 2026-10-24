import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/compare/compare_page.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';
import 'package:flutwire/src/ui/widgets/call_tile.dart';

import 'calls.dart';
import 'fake_session.dart';
import 'harness.dart';

Future<FakeSession> openDetail(
  WidgetTester tester,
  FlutwireCall call, {
  List<FlutwireCall> more = const [],
  bool canResend = true,
}) async {
  setScreen(tester, const Size(420, 900));
  final session = FakeSession(calls: [call, ...more])..canResend = canResend;
  await tester.pumpWidget(
    inspectorApp(session, CallDetailPage(callId: call.id)),
  );
  await settle(tester);
  return session;
}

void main() {
  group('the way into the editor', () {
    testWidgets('is a button in the call, which opens the editor', (
      tester,
    ) async {
      await openDetail(tester, makeCall(1, method: 'POST'));

      await tester.tap(find.byTooltip('Edit and resend'));
      await settle(tester);

      expect(find.text('Edit and resend'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('is not offered where nothing can be sent', (tester) async {
      await openDetail(tester, makeCall(1), canResend: false);

      expect(find.byTooltip('Edit and resend'), findsNothing);
    });

    FlutwireCall holding(FlutwireConversationKind kind) => makeCall(1).copyWith(
      messages: FlutwireMessages(
        kind: kind,
        items: const [],
        total: 0,
        keptBytes: 0,
      ),
    );

    testWidgets('is not offered for a WebSocket', (tester) async {
      await openDetail(tester, holding(FlutwireConversationKind.webSocket));

      expect(find.byTooltip('Edit and resend'), findsNothing);
    });

    testWidgets('is offered for an event stream', (tester) async {
      await openDetail(tester, holding(FlutwireConversationKind.eventStream));

      expect(find.byTooltip('Edit and resend'), findsOneWidget);
    });

    testWidgets('is not offered for a callable function', (tester) async {
      await openDetail(
        tester,
        makeCall(1, source: FlutwireSource.functions, method: 'CALL'),
      );

      expect(find.byTooltip('Edit and resend'), findsNothing);
    });
  });

  group('a call that was sent again', () {
    testWidgets('names the call it repeats, and opens it', (tester) async {
      final original = makeCall(
        1,
        method: 'POST',
        url: 'https://api.test/orders?x=1',
      );
      await openDetail(
        tester,
        makeCall(
          2,
          method: 'POST',
          url: 'https://staging.test/orders',
          resentFrom: 1,
        ),
        more: [original],
      );

      expect(find.text('Sent again from'), findsOneWidget);
      expect(find.text('POST  api.test/orders?x=1'), findsOneWidget);

      await tester.tap(find.text('POST  api.test/orders?x=1'));
      await settle(tester);

      expect(find.text('POST  api.test'), findsOneWidget);
    });

    testWidgets('can be compared with the call it repeats', (tester) async {
      final original = makeCall(1, url: 'https://api.test/orders');
      await openDetail(
        tester,
        makeCall(2, url: 'https://staging.test/orders', resentFrom: 1),
        more: [original],
      );

      await tester.tap(find.text('Compare with the original'));
      await settle(tester);

      expect(find.byType(ComparePage), findsOneWidget);
      // The original is on the left.
      expect(
        tester.getTopLeft(find.text('api.test').first).dx,
        lessThan(tester.getTopLeft(find.text('staging.test').first).dx),
      );
    });

    testWidgets('has nothing to compare with once the original is gone', (
      tester,
    ) async {
      await openDetail(tester, makeCall(2, resentFrom: 1));

      expect(find.text('Compare with the original'), findsNothing);
    });

    testWidgets('says so when that call is gone from the history', (
      tester,
    ) async {
      await openDetail(tester, makeCall(2, resentFrom: 1));

      expect(find.text('Sent again from'), findsOneWidget);
      expect(
        find.text('A call that is no longer in the history'),
        findsOneWidget,
      );
    });

    testWidgets('has no such line when it repeats nothing', (tester) async {
      await openDetail(tester, makeCall(2));

      expect(find.text('Sent again from'), findsNothing);
    });

    testWidgets('is marked in the list', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlutwire(
        tester,
        Column(
          children: [
            CallTile(
              call: makeCall(2, resentFrom: 1),
              now: DateTime.utc(2026, 10, 23, 12, 1),
            ),
            CallTile(call: makeCall(3), now: DateTime.utc(2026, 10, 23, 12, 1)),
          ],
        ),
      );

      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Sent again')), findsOneWidget);
      semantics.dispose();
    });
  });
}
