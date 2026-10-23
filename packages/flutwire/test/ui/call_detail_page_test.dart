import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';

import 'calls.dart';

Future<void> open(
  WidgetTester tester,
  FlutwireCall call, {
  List<FlutwireCall> more = const [],
  Size size = const Size(420, 900),
}) async {
  setScreen(tester, size);
  await startFlutwire(tester, calls: [call, ...more]);
  await tester.pumpWidget(inspectorApp(CallDetailPage(callId: call.id)));
  await settle(tester);
}

void main() {
  tearDown(stopFlutwire);

  testWidgets('the overview says what was asked and what came back', (
    tester,
  ) async {
    await open(
      tester,
      makeCall(
        1,
        method: 'POST',
        url: 'https://api.test/clubs?x=1',
        status: 201,
        millis: 450,
        responseBody: '{"club":"Orion"}',
      ),
    );

    expect(find.text('POST  api.test'), findsOneWidget);
    expect(find.text('https://api.test/clubs?x=1'), findsOneWidget);
    expect(find.text('201 Created'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
  });

  testWidgets('a failed call shows the error', (tester) async {
    await open(
      tester,
      makeCall(
        1,
        status: null,
        state: FlutwireCallState.failed,
        error: const FlutwireError(
          type: 'SocketException',
          message: 'Connection refused',
        ),
      ),
    );

    expect(find.textContaining('SocketException'), findsWidgets);
    expect(find.textContaining('Connection refused'), findsWidgets);
  });

  testWidgets('the response tab shows the body in the viewer', (tester) async {
    await open(
      tester,
      makeCall(1, responseBody: '{"club":"Orion","members":3}'),
    );

    await tester.tap(find.text('Response'));
    await settle(tester);

    expect(find.textContaining('Orion'), findsWidgets);
  });

  testWidgets('the request tab shows the request body', (tester) async {
    await open(
      tester,
      makeCall(
        1,
        method: 'POST',
        requestBody: '{"name":"Vega"}',
        requestHeaders: {'content-type': 'application/json'},
      ),
    );

    await tester.tap(find.text('Request'));
    await settle(tester);

    expect(find.textContaining('Vega'), findsWidgets);
  });

  testWidgets('headers are one tap away, with their values', (tester) async {
    await open(
      tester,
      makeCall(
        1,
        responseHeaders: {
          'x-request-id': 'abc123',
          'content-type': 'text/plain',
        },
      ),
    );

    await tester.tap(find.text('Response'));
    await settle(tester);
    await tester.tap(find.text('Headers'));
    await settle(tester);

    expect(find.textContaining('x-request-id'), findsWidgets);
    expect(find.textContaining('abc123'), findsWidgets);
  });

  testWidgets('a call that is not in the history says so', (tester) async {
    setScreen(tester, const Size(420, 900));
    await startFlutwire(tester);
    await tester.pumpWidget(inspectorApp(const CallDetailPage(callId: 99)));
    await settle(tester);

    expect(find.text('This call is no longer in the history'), findsOneWidget);
  });

  testWidgets('a call that leaves the history while it is open says so', (
    tester,
  ) async {
    await open(tester, makeCall(1));
    expect(find.text('This call is no longer in the history'), findsNothing);

    await tester.runAsync(() => Flutwire.store!.remove([1]));
    (Flutwire.store! as MemoryFlutwireStore).flush();
    await settle(tester, 1000);

    expect(find.text('This call is no longer in the history'), findsOneWidget);
  });

  testWidgets('the pin in the bar pins the call, and again unpins it', (
    tester,
  ) async {
    await open(tester, makeCall(1));
    expect(Flutwire.store!.find(1)!.pinned, isFalse);

    await tester.tap(find.byTooltip('Pin'));
    await settle(tester, 1000);
    expect(Flutwire.store!.find(1)!.pinned, isTrue);

    await tester.tap(find.byTooltip('Unpin'));
    await settle(tester, 1000);
    expect(Flutwire.store!.find(1)!.pinned, isFalse);
  });

  group('the menu', () {
    String? copied;

    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('copies the URL', (tester) async {
      await open(tester, makeCall(1, url: 'https://api.test/clubs'));

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Copy URL'));
      await settle(tester);

      expect(copied, 'https://api.test/clubs');
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('copies the call as a cURL command', (tester) async {
      await open(
        tester,
        makeCall(1, method: 'DELETE', url: 'https://api.test/clubs/7'),
      );

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Copy as cURL'));
      await settle(tester);

      expect(copied, contains("curl -X DELETE 'https://api.test/clubs/7'"));
    });
  });

  testWidgets('beside the list it shows no back arrow', (tester) async {
    setScreen(tester, const Size(1200, 800));
    await startFlutwire(tester, calls: [makeCall(1)]);
    await tester.pumpWidget(
      inspectorApp(const CallDetailPage(callId: 1, embedded: true)),
    );
    await settle(tester);

    expect(find.byType(BackButton), findsNothing);
  });
}
