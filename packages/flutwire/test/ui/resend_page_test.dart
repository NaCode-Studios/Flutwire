import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/resend/resend_page.dart';
import 'package:flutwire/src/ui/shell.dart';

import 'calls.dart';
import 'fake_session.dart';

/// A session whose history holds [call] and the call that sending it again
/// will have recorded, which is what `resend` answers with.
FakeSession sessionFor(FlutwireCall call, {FakeSession? session}) {
  final fake = session ?? FakeSession(calls: [call, _answer(call.id)]);
  fake.resendAnswer = 99;
  return fake;
}

FlutwireCall _answer(int from) => makeCall(
  99,
  method: 'PUT',
  url: 'https://sent.test/clubs',
  resentFrom: from,
);

/// Opens the editor on top of a page, so there is a route to go back to.
Future<FakeSession> open(
  WidgetTester tester,
  FlutwireCall call, {
  FakeSession? session,
}) async {
  setScreen(tester, const Size(420, 900));
  final fake = sessionFor(call, session: session);
  await tester.pumpWidget(
    inspectorApp(
      fake,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                shellRoute(
                  fake,
                  name: 'test',
                  child: ResendPage(call: call),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  return fake;
}

Finder field(String text) => find.widgetWithText(TextField, text);

FlutwireCall orderCall({
  String method = 'POST',
  String url = 'https://api.test/clubs?x=1',
  Map<String, String> headers = const {},
  String? body = '{"name":"Vega"}',
  FlutwireBody? bodyOf,
}) => makeCall(
  5,
  method: method,
  url: url,
  requestBody: body,
  requestBodyOf: bodyOf,
  requestHeaders: {'content-type': 'application/json', ...headers},
);

FlutwireBody binary(List<int> bytes, {int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(bytes),
  totalBytes: total,
  contentType: 'application/octet-stream',
);

void main() {
  testWidgets('starts as the call was, without what the client writes', (
    tester,
  ) async {
    await open(
      tester,
      orderCall(
        headers: {'x-trace': 'abc', 'host': 'api.test', 'content-length': '15'},
      ),
    );

    expect(find.text('Edit and resend'), findsOneWidget);
    expect(field('https://api.test/clubs?x=1'), findsOneWidget);
    expect(field('x-trace'), findsOneWidget);
    expect(field('abc'), findsOneWidget);
    expect(field('content-type'), findsOneWidget);
    expect(field('host'), findsNothing);
    expect(field('content-length'), findsNothing);
    expect(field('{"name":"Vega"}'), findsOneWidget);
    expect(find.text('Sends a real request to api.test.'), findsOneWidget);
  });

  testWidgets('sends what was changed, and opens the call it made', (
    tester,
  ) async {
    final session = await open(tester, orderCall(headers: {'x-trace': 'abc'}));

    await tester.enterText(
      field('https://api.test/clubs?x=1'),
      'https://sent.test/clubs',
    );
    await tester.enterText(field('abc'), 'edited');
    await tester.enterText(field('{"name":"Vega"}'), '{"name":"Lyra"}');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text('PUT').last);
    await settle(tester);
    await tester.tap(find.text('Send'));
    await settle(tester);

    final sent = session.resent.single;
    expect(sent.from, 5);
    expect(sent.method, 'PUT');
    expect(sent.uri.toString(), 'https://sent.test/clubs');
    expect(sent.headers.first('x-trace'), 'edited');
    expect(sent.headers.first('content-type'), 'application/json');
    expect(utf8.decode(sent.body!), '{"name":"Lyra"}');
    // The call that was made is open now, in place of the editor.
    expect(find.text('PUT  sent.test'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
  });

  testWidgets('adds a header field and takes one away', (tester) async {
    final session = await open(
      tester,
      orderCall(headers: {'x-trace': 'abc', 'x-old': 'gone'}),
    );

    await tester.tap(find.text('Add header'));
    await settle(tester);
    // The new row is the last pair of fields: name, then value.
    final names = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Name',
    );
    final values = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Value',
    );
    await tester.enterText(names.last, 'x-new');
    await tester.enterText(values.last, 'fresh');
    await tester.tap(find.byTooltip('Remove header').at(2));
    await settle(tester);
    await tester.tap(find.text('Send'));
    await settle(tester);

    final headers = session.resent.single.headers;
    expect(headers.first('x-new'), 'fresh');
    expect(headers.first('x-trace'), 'abc');
    expect(headers.contains('x-old'), isFalse);
  });

  group('a value the redaction hid', () {
    testWidgets('is flagged, named in a note, and not sent', (tester) async {
      final session = await open(
        tester,
        orderCall(headers: {'authorization': '[redacted]', 'x-keep': '1'}),
      );

      expect(
        find.textContaining('Not sent, because Flutwire hid their values'),
        findsOneWidget,
      );
      expect(find.byTooltip('Hidden'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await settle(tester);

      final sent = session.resent.single;
      expect(sent.headers.contains('authorization'), isFalse);
      expect(sent.headers.first('x-keep'), '1');
      expect(sent.hidden, ['authorization']);
    });

    testWidgets('is sent once a value is typed over it', (tester) async {
      final session = await open(
        tester,
        orderCall(headers: {'authorization': '[redacted]'}),
      );

      await tester.enterText(field('[redacted]'), 'Bearer typed');
      await settle(tester);

      expect(find.textContaining('Not sent'), findsNothing);
      expect(find.byTooltip('Hidden'), findsNothing);

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(
        session.resent.single.headers.first('authorization'),
        'Bearer typed',
      );
    });

    testWidgets('is flagged in the address until it is replaced', (
      tester,
    ) async {
      await open(
        tester,
        orderCall(url: 'https://api.test/clubs?api_key=%5Bredacted%5D'),
      );

      expect(
        find.textContaining('A value in the address was hidden'),
        findsOneWidget,
      );

      await tester.enterText(
        field('https://api.test/clubs?api_key=%5Bredacted%5D'),
        'https://api.test/clubs?api_key=typed',
      );
      await settle(tester);

      expect(find.textContaining('A value in the address'), findsNothing);
    });

    testWidgets('is flagged in the body until it is replaced', (tester) async {
      final session = await open(
        tester,
        orderCall(body: '{"user":"vega","password":"[redacted]"}'),
      );

      expect(
        find.textContaining('Some values in the body were hidden'),
        findsOneWidget,
      );

      await tester.enterText(
        field('{"user":"vega","password":"[redacted]"}'),
        '{"user":"vega","password":"typed"}',
      );
      await settle(tester);

      expect(find.textContaining('Some values in the body'), findsNothing);

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(
        utf8.decode(session.resent.single.body!),
        '{"user":"vega","password":"typed"}',
      );
    });

    testWidgets('is flagged in a cookie that still holds the mask', (
      tester,
    ) async {
      final session = await open(
        tester,
        orderCall(headers: {'cookie': 'session=[redacted]; theme=dark'}),
      );

      expect(find.byTooltip('Hidden'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(session.resent.single.headers.first('cookie'), 'theme=dark');
    });
  });

  testWidgets('does not send to an address it cannot reach', (tester) async {
    final session = await open(tester, orderCall());

    await tester.enterText(field('https://api.test/clubs?x=1'), 'not a url');
    await tester.tap(find.text('Send'));
    await settle(tester);

    expect(
      find.text('Enter a full address, such as https://example.com/path.'),
      findsOneWidget,
    );
    expect(session.resent, isEmpty);

    await tester.enterText(field('not a url'), 'ftp://files.test/a');
    await tester.tap(find.text('Send'));
    await settle(tester);

    expect(session.resent, isEmpty);
  });

  group('the body', () {
    testWidgets('of a call that had none is not sent', (tester) async {
      final session = await open(tester, orderCall(method: 'GET', body: null));

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(session.resent.single.body, isNull);
    });

    testWidgets('says when only the start of it was recorded', (tester) async {
      await open(
        tester,
        orderCall(
          bodyOf: FlutwireBody(
            bytes: Uint8List.fromList(utf8.encode('{"a":')),
            totalBytes: 5000,
            contentType: 'application/json',
          ),
        ),
      );

      expect(
        find.text(
          'The body was cut at 5 B of 4.9 KB. This is only the start of it.',
        ),
        findsOneWidget,
      );
      expect(field('{"a":'), findsOneWidget);
    });

    testWidgets('that is not text goes out as it was recorded', (tester) async {
      final session = await open(
        tester,
        orderCall(bodyOf: binary([1, 2, 3, 4])),
      );

      expect(
        find.text(
          'A body that is not text, 4 B. It is sent as it was recorded.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(session.resent.single.body, [1, 2, 3, 4]);
    });

    testWidgets('that is not text can be left out', (tester) async {
      final session = await open(
        tester,
        orderCall(bodyOf: binary([1, 2, 3, 4])),
      );

      await tester.tap(find.byType(Switch));
      await settle(tester);
      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(session.resent.single.body, isNull);
    });

    testWidgets('that is not text and was cut is not sent', (tester) async {
      final session = await open(
        tester,
        orderCall(bodyOf: binary([1, 2], total: 100)),
      );

      expect(
        find.text('Only part of this body was recorded, so it is not sent.'),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(session.resent.single.body, isNull);
    });
  });

  group('when sending does not go as planned', () {
    testWidgets('a request that cannot leave says so and stays', (
      tester,
    ) async {
      final session = await open(tester, orderCall());
      session.onResend = (_) async => throw StateError('no route');

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(find.text('The request could not be sent.'), findsOneWidget);
      expect(find.text('Edit and resend'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('a call that could not be recorded says so and goes back', (
      tester,
    ) async {
      final session = await open(tester, orderCall());
      session.resendAnswer = null;

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(
        find.text('Sent, but Flutwire could not record it.'),
        findsOneWidget,
      );
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Edit and resend'), findsNothing);
    });
  });

  testWidgets('speaks Italian when the app does', (tester) async {
    final session = FakeSession(
      config: const FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: Locale('it'),
        notification: FlutwireNotificationConfig(enabled: false),
      ),
      calls: [orderCall(), _answer(5)],
    );

    await open(tester, orderCall(), session: session);

    expect(find.text('Modifica e reinvia'), findsOneWidget);
    expect(find.text('Invia'), findsOneWidget);
    expect(find.text('Aggiungi header'), findsOneWidget);
    expect(find.text('Invia una richiesta vera a api.test.'), findsOneWidget);
  });
}
