import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/compare/compare_page.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';

import 'calls.dart';
import 'fake_session.dart';

/// A tall screen, so that every part of the page is built at once.
const _tall = Size(420, 2600);

Future<FakeSession> open(
  WidgetTester tester,
  FlutwireCall left,
  FlutwireCall right, {
  Size size = _tall,
}) async {
  setScreen(tester, size);
  final session = FakeSession(calls: [left, right]);
  await tester.pumpWidget(
    inspectorApp(session, ComparePage(leftId: left.id, rightId: right.id)),
  );
  await settle(tester);
  return session;
}

FlutwireCall _first() => makeCall(
  1,
  url: 'https://api.test/items/1?page=1',
  millis: 120,
  requestHeaders: {'accept': 'application/json', 'x-id': 'a1'},
  responseHeaders: {'content-type': 'application/json', 'etag': '"v1"'},
  responseBody: '{"id":1,"title":"one","tags":["a"]}',
);

FlutwireCall _second() => makeCall(
  2,
  url: 'https://api.test/items/2?page=2',
  status: 404,
  millis: 300,
  requestHeaders: {'accept': 'application/json', 'x-id': 'b2', 'x-trace': 't'},
  responseHeaders: {'content-type': 'application/json'},
  responseBody: '{"id":2,"title":"one","tags":["a"]}',
);

FlutwireBody _bytes(List<int> bytes, {int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(bytes),
  totalBytes: total,
  contentType: 'application/octet-stream',
);

FlutwireBody _form(String text) => FlutwireBody(
  bytes: Uint8List.fromList(text.codeUnits),
  contentType: 'application/x-www-form-urlencoded',
);

Finder _line(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
);

void main() {
  testWidgets('sets the two calls side by side', (tester) async {
    await open(tester, _first(), _second());

    expect(find.text('Compare'), findsOneWidget);
    // Once in the card of each call and once in the overview.
    expect(find.text('/items/1'), findsNWidgets(2));
    expect(find.text('/items/2'), findsNWidgets(2));
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('QUERY PARAMETERS'), findsOneWidget);
    expect(find.text('REQUEST HEADERS'), findsOneWidget);
    expect(find.text('RESPONSE HEADERS'), findsOneWidget);
    expect(find.text('RESPONSE BODY'), findsOneWidget);
  });

  testWidgets('says how many things differ in each part', (tester) async {
    await open(tester, _first(), _second());

    // The path, the status, the time and the time to the first byte.
    expect(find.text('4 differences'), findsOneWidget);
    // The page, the etag and the id.
    expect(find.text('1 difference'), findsNWidgets(3));
    // The header that changed and the one only the right side has.
    expect(find.text('2 differences'), findsOneWidget);
  });

  testWidgets('shows only what differs until asked for the rest', (
    tester,
  ) async {
    await open(tester, _first(), _second());

    expect(find.text('x-id'), findsOneWidget);
    expect(find.text('x-trace'), findsOneWidget);
    expect(find.text('etag'), findsOneWidget);
    expect(find.text('accept'), findsNothing);
    expect(find.text('content-type'), findsNothing);

    await tester.tap(find.text('Differences only'));
    await settle(tester);

    expect(find.text('accept'), findsOneWidget);
    expect(find.text('content-type'), findsOneWidget);
  });

  testWidgets('puts the changed line of a body against the new one', (
    tester,
  ) async {
    await open(tester, _first(), _second());

    expect(_line('  "id": 1,'), findsOneWidget);
    expect(_line('  "id": 2,'), findsOneWidget);
    // Two lines after it are the same, which is what is shown, and the three
    // that follow are left out.
    expect(_line('  "title": "one",'), findsNWidgets(2));
    expect(_line('  "tags": ['), findsNWidgets(2));
    expect(_line('    "a"'), findsNothing);
    expect(find.text('3 identical lines'), findsOneWidget);
  });

  testWidgets('shows every line when asked to', (tester) async {
    await open(tester, _first(), _second());

    await tester.tap(find.text('Differences only'));
    await settle(tester);

    expect(_line('  "tags": ['), findsNWidgets(2));
    expect(find.textContaining('identical line'), findsNothing);
  });

  testWidgets('says so when a part is the same on both sides', (tester) async {
    final a = makeCall(
      1,
      requestHeaders: {'accept': 'text/plain'},
      responseBody: '{"ok":true}',
    );
    final b = makeCall(
      2,
      requestHeaders: {'accept': 'text/plain'},
      responseBody: '{"ok":true}',
    );

    await open(tester, a, b);

    // The overview, the request headers and the body of the response.
    expect(find.text('Identical'), findsNWidgets(3));
    expect(find.text('REQUEST HEADERS'), findsOneWidget);
    expect(find.text('accept'), findsNothing);
  });

  testWidgets('leaves out the body that neither call has', (tester) async {
    await open(tester, _first(), _second());

    expect(find.text('REQUEST BODY'), findsNothing);
  });

  testWidgets('marks a field that only one side has', (tester) async {
    await open(tester, _first(), _second());

    // x-trace is the right side's alone.
    expect(find.text('Missing'), findsNWidgets(2));
  });

  testWidgets('swaps the two sides', (tester) async {
    await open(tester, _first(), _second());
    double at(String text) => tester.getTopLeft(find.text(text).first).dx;
    expect(at('/items/1'), lessThan(at('/items/2')));

    await tester.tap(find.byTooltip('Swap sides'));
    await settle(tester);

    expect(at('/items/2'), lessThan(at('/items/1')));
    // What was added is now what was removed: the right side lacks x-trace.
    expect(find.text('Missing'), findsNWidgets(2));
  });

  testWidgets('compares a form field by field', (tester) async {
    final a = makeCall(1, method: 'POST', requestBodyOf: _form('a=1&b=2'));
    final b = makeCall(2, method: 'POST', requestBodyOf: _form('a=1&b=3&c=4'));

    await open(tester, a, b);

    expect(find.text('REQUEST BODY'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    expect(find.text('a'), findsNothing);
  });

  testWidgets('compares bytes that are not text as bytes', (tester) async {
    final same = makeCall(
      1,
      method: 'POST',
      requestBodyOf: _bytes([0, 1, 2, 3]),
    );
    final alike = makeCall(
      2,
      method: 'POST',
      requestBodyOf: _bytes([0, 1, 2, 3]),
    );
    await open(tester, same, alike);
    expect(find.text('Same bytes (4 B)'), findsOneWidget);
  });

  testWidgets('says when bytes that are not text differ', (tester) async {
    final a = makeCall(1, method: 'POST', requestBodyOf: _bytes([0, 1, 2, 3]));
    final b = makeCall(
      2,
      method: 'POST',
      requestBodyOf: _bytes([0, 1, 2, 3, 4]),
    );

    await open(tester, a, b);

    expect(find.text('Different bytes: 4 B against 5 B'), findsOneWidget);
  });

  testWidgets('says that a body was cut, and on which side', (tester) async {
    final a = makeCall(
      1,
      method: 'POST',
      requestBodyOf: _bytes([65, 66], total: 4096),
    );
    final b = makeCall(2, method: 'POST', requestBodyOf: _bytes([65, 66]));

    await open(tester, a, b);

    expect(find.text('Side A is cut: 2 B of 4.0 KB shown.'), findsOneWidget);
    expect(find.textContaining('Side B is cut'), findsNothing);
  });

  testWidgets('compares a call that has no response with one that has', (
    tester,
  ) async {
    final failed = makeCall(
      1,
      status: null,
      state: FlutwireCallState.failed,
      error: const FlutwireError(type: 'SocketException', message: 'no route'),
    );
    final worked = makeCall(2, responseBody: '{"ok":true}');

    await open(tester, failed, worked);

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('200 OK'), findsOneWidget);
    expect(find.text('RESPONSE BODY'), findsOneWidget);
  });

  testWidgets('opens a call when its card is tapped', (tester) async {
    await open(tester, _first(), _second());

    await tester.tap(find.text('/items/2').first);
    await settle(tester);

    expect(find.byType(CallDetailPage), findsOneWidget);
    expect(find.text('https://api.test/items/2?page=2'), findsOneWidget);
  });

  testWidgets('says so when one of the calls is gone', (tester) async {
    final session = await open(tester, _first(), _second());

    await session.store.remove([2]);
    session.store.flush();
    await settle(tester);

    expect(find.text('This call is no longer in the history'), findsOneWidget);
  });

  testWidgets('follows a call that is still running', (tester) async {
    final running = makeCall(1, status: null, state: FlutwireCallState.pending);
    final session = await open(tester, running, _second());
    expect(find.text('Running'), findsOneWidget);

    session.store.put(
      makeCall(1, url: 'https://api.test/items', responseBody: '{"ok":true}'),
    );
    session.store.flush();
    await settle(tester, 800);

    expect(find.text('Running'), findsNothing);
    expect(find.text('200 OK'), findsOneWidget);
  });

  testWidgets('reads in Italian', (tester) async {
    setScreen(tester, _tall);
    final session = FakeSession(
      config: const FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: Locale('it'),
        notification: FlutwireNotificationConfig(enabled: false),
      ),
      calls: [_first(), _second()],
    );
    await tester.pumpWidget(
      inspectorApp(session, const ComparePage(leftId: 1, rightId: 2)),
    );
    await settle(tester);

    expect(find.text('Confronta'), findsOneWidget);
    expect(find.text('Solo differenze'), findsOneWidget);
    expect(find.text('4 differenze'), findsOneWidget);
    expect(find.text('Assente'), findsNWidgets(2));
  });
}
