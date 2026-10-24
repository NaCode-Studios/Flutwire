import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/breakpoints.dart';
import 'package:flutwire/src/intercept/interception.dart';
import 'package:flutwire/src/intercept/rule.dart';
import 'package:flutwire/src/session.dart';
import 'package:flutwire/src/ui/detail/call_detail_page.dart';
import 'package:flutwire/src/ui/inspector/inspector_page.dart';
import 'package:flutwire/src/ui/intercept/rule_editor_page.dart';
import 'package:flutwire/src/ui/intercept/rules_page.dart';
import 'package:flutwire/src/ui/resend/resend_page.dart';

import 'calls.dart';
import 'fake_session.dart';

const _on = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  locale: Locale('en'),
  interception: true,
  notification: FlutwireNotificationConfig(enabled: false),
);

FakeSession _session({List<FlutwireCall> calls = const []}) {
  final session = FakeSession(config: _on, calls: calls);
  session.interception = FlutwireInterception(session.store.preferences);
  return session;
}

FlutwireHoldTicket _hold(
  FlutwireSession session, {
  String method = 'POST',
  String url = 'https://api.test/orders',
  Map<String, String> headers = const {'x-demo': '1'},
  String body = '{"qty":1}',
  String? ruleId,
}) => session.interception!.breakpoints.hold(
  method: method,
  uri: Uri.parse(url),
  headers: FlutwireHeaders.fromMap({
    ...headers,
    'content-type': 'application/json',
  }),
  body: Uint8List.fromList(utf8.encode(body)),
  ruleId: ruleId,
);

Future<void> _openInspector(WidgetTester tester, FakeSession session) async {
  setScreen(tester, const Size(420, 1000));
  await tester.pumpWidget(inspectorApp(session, const InspectorPage()));
  await settle(tester);
}

FlutwireRule _breakpoint(FlutwireInterception interception, String pattern) {
  final rule = FlutwireRule(
    id: interception.rules.newId(),
    kind: FlutwireRuleKind.breakpoint,
    pattern: pattern,
  );
  interception.rules.add(rule);
  return rule;
}

void main() {
  group('a request that is held', () {
    testWidgets('opens its editor by itself', (tester) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);

      _hold(session);
      await settle(tester);

      expect(find.byType(ResendPage), findsOneWidget);
      expect(find.text('Held request'), findsOneWidget);
      expect(find.textContaining('the app is waiting for it'), findsOneWidget);
      expect(find.text('Stop the request'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('https://api.test/orders'), findsOneWidget);
    });

    testWidgets('opens its editor when the inspector comes up after it', (
      tester,
    ) async {
      final session = _session();
      _hold(session);

      await _openInspector(tester, session);

      expect(find.text('Held request'), findsOneWidget);
    });

    testWidgets('shows the request as it really is, secrets included', (
      tester,
    ) async {
      final session = _session();
      await _openInspector(tester, session);

      _hold(session, headers: {'authorization': 'Bearer secret'});
      await settle(tester);

      expect(find.text('Bearer secret'), findsOneWidget);
      expect(find.textContaining('hidden'), findsNothing);
    });

    testWidgets('goes on as it is written when it is sent', (tester) async {
      final session = _session();
      await _openInspector(tester, session);
      final ticket = _hold(session);
      await settle(tester);

      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.controller?.text == 'https://api.test/orders',
        ),
        'https://staging.test/orders',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '{"qty":1}',
        ),
        '{"qty":2}',
      );
      await tester.tap(find.text('Send'));
      await settle(tester);

      final sent = (await ticket.answer)!;
      expect(sent.uri.host, 'staging.test');
      expect(utf8.decode(sent.body), '{"qty":2}');
      expect(sent.method, 'POST');
      expect(sent.headers.first('x-demo'), '1');
      expect(find.byType(ResendPage), findsNothing);
      expect(session.interception!.breakpoints.held, isEmpty);
    });

    testWidgets('goes on as it was when nothing was changed', (tester) async {
      final session = _session();
      await _openInspector(tester, session);
      final held = _hold(session);
      await settle(tester);
      final request = session.interception!.breakpoints.find(held.id)!;

      await tester.tap(find.text('Send'));
      await settle(tester);

      final sent = (await held.answer)!;
      expect(sent.method, request.method);
      expect(sent.uri, request.uri);
      expect(sent.headers, request.headers);
      expect(sent.body, request.body);
    });

    testWidgets('is stopped from its editor', (tester) async {
      final session = _session();
      await _openInspector(tester, session);
      final ticket = _hold(session);
      await settle(tester);

      await tester.tap(find.text('Stop the request'));
      await settle(tester);

      expect(await ticket.answer, isNull);
      expect(find.byType(ResendPage), findsNothing);
    });

    testWidgets('closes its editor when it is let go some other way', (
      tester,
    ) async {
      final session = _session();
      await _openInspector(tester, session);
      final ticket = _hold(session);
      await settle(tester);

      session.interception!.breakpoints.stop(ticket.id);
      await settle(tester);

      expect(find.byType(ResendPage), findsNothing);
      expect(find.text('This request is not held any more.'), findsOneWidget);
    });

    testWidgets('hands over to the next one when it is sent', (tester) async {
      final session = _session();
      final first = _hold(session, url: 'https://api.test/first');
      _hold(session, url: 'https://api.test/second');
      await _openInspector(tester, session);
      expect(find.text('https://api.test/first'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await settle(tester);

      expect((await first.answer)!.uri.path, '/first');
      expect(find.byType(ResendPage, skipOffstage: false), findsOneWidget);
      expect(find.text('https://api.test/second'), findsOneWidget);
    });

    testWidgets('hands over to the next one when it is stopped', (
      tester,
    ) async {
      final session = _session();
      final first = _hold(session, url: 'https://api.test/first');
      _hold(session, url: 'https://api.test/second');
      await _openInspector(tester, session);

      await tester.tap(find.text('Stop the request'));
      await settle(tester);

      expect(await first.answer, isNull);
      expect(find.byType(ResendPage, skipOffstage: false), findsOneWidget);
      expect(find.text('https://api.test/second'), findsOneWidget);
    });

    testWidgets('leaves only its own page when it is let go from outside', (
      tester,
    ) async {
      final session = _session();
      final first = _hold(session, url: 'https://api.test/first');
      _hold(session, url: 'https://api.test/second');
      await _openInspector(tester, session);

      session.interception!.breakpoints.stop(first.id);
      await settle(tester);

      expect(find.byType(ResendPage, skipOffstage: false), findsOneWidget);
      expect(find.text('https://api.test/second'), findsOneWidget);
    });

    testWidgets('closes its editor when its breakpoint is switched off', (
      tester,
    ) async {
      final session = _session();
      await _openInspector(tester, session);
      final rule = _breakpoint(session.interception!, 'api.test/*');
      final ticket = _hold(session, ruleId: rule.id);
      await settle(tester);
      expect(find.byType(ResendPage), findsOneWidget);

      session.interception!.rules.setEnabled(rule.id, enabled: false);
      await settle(tester);

      expect((await ticket.answer)?.uri.path, '/orders');
      expect(find.byType(ResendPage, skipOffstage: false), findsNothing);
    });

    testWidgets('can be sent with a header taken away', (tester) async {
      final session = _session();
      await _openInspector(tester, session);
      final ticket = _hold(session);
      await settle(tester);

      await tester.tap(find.byTooltip('Remove header').first);
      await settle(tester);
      await tester.tap(find.text('Send'));
      await settle(tester);

      final sent = (await ticket.answer)!;
      expect(sent.headers.contains('x-demo'), isFalse);
      expect(sent.headers.contains('content-type'), isTrue);
    });
  });

  group('the banner above the list', () {
    testWidgets('is not there while there is nothing to say', (tester) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);

      expect(find.textContaining('rule'), findsNothing);
      expect(find.textContaining('held'), findsNothing);
    });

    testWidgets('is not there where the rules are off', (tester) async {
      await _openInspector(tester, FakeSession(calls: [makeCall(1)]));

      expect(find.textContaining('in force'), findsNothing);
    });

    testWidgets('counts the rules in force and opens them', (tester) async {
      final session = _session(calls: [makeCall(1)]);
      _breakpoint(session.interception!, 'api.test/a');
      final off = _breakpoint(session.interception!, 'api.test/b');
      session.interception!.rules.setEnabled(off.id, enabled: false);
      await _openInspector(tester, session);

      expect(find.text('1 rule in force'), findsOneWidget);

      await tester.tap(find.text('1 rule in force'));
      await settle(tester);
      expect(find.byType(RulesPage), findsOneWidget);
    });

    testWidgets('says that a request is held, and reopens its editor', (
      tester,
    ) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);
      _hold(session);
      await settle(tester);
      expect(find.byType(ResendPage), findsOneWidget);

      // The editor was left without sending or stopping the request.
      await tester.tap(find.byType(BackButton));
      await settle(tester);

      expect(find.byType(ResendPage), findsNothing);
      expect(find.text('1 request is held at a breakpoint'), findsOneWidget);
      await tester.tap(find.text('Review'));
      await settle(tester);
      expect(find.byType(ResendPage), findsOneWidget);
    });

    testWidgets('does not open an editor again for what it opened once', (
      tester,
    ) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);
      _hold(session);
      await settle(tester);
      await tester.tap(find.byType(BackButton));
      await settle(tester);

      // Anything that changes the rules or the held requests is heard by it.
      _breakpoint(session.interception!, 'api.test/new');
      await settle(tester);

      expect(find.byType(ResendPage), findsNothing);
    });

    testWidgets('opens the editor of each request as it comes', (tester) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);

      _hold(session);
      await settle(tester);
      _hold(session, url: 'https://api.test/second');
      await settle(tester);

      // The first editor is still in the stack, under the second.
      expect(find.byType(ResendPage, skipOffstage: false), findsNWidgets(2));
      expect(find.byType(ResendPage), findsOneWidget);
      expect(find.text('https://api.test/second'), findsOneWidget);
    });

    testWidgets('speaks Italian when the app does', (tester) async {
      final session = FakeSession(
        config: const FlutwireConfig(
          enabled: true,
          captureDartIo: false,
          persist: false,
          shortcut: false,
          locale: Locale('it'),
          interception: true,
          notification: FlutwireNotificationConfig(enabled: false),
        ),
        calls: [makeCall(1)],
      );
      session.interception = FlutwireInterception(session.store.preferences);
      await _openInspector(tester, session);

      _hold(session);
      await settle(tester);
      expect(find.text('Richiesta trattenuta'), findsOneWidget);
      expect(find.text('Ferma la richiesta'), findsOneWidget);
    });
  });

  group('the way into the rules', () {
    testWidgets('is an entry in the menu of the inspector', (tester) async {
      final session = _session(calls: [makeCall(1)]);
      await _openInspector(tester, session);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Mocks and breakpoints'));
      await settle(tester);

      expect(find.byType(RulesPage), findsOneWidget);
    });

    testWidgets(
      'is there where the rules are off, to say how to turn them on',
      (tester) async {
        await _openInspector(tester, FakeSession(calls: [makeCall(1)]));

        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await settle(tester);
        await tester.tap(find.text('Mocks and breakpoints'));
        await settle(tester);

        expect(find.textContaining('interception: true'), findsOneWidget);
      },
    );
  });

  group('a call in its own page', () {
    Future<void> openDetail(
      WidgetTester tester,
      FakeSession session,
      FlutwireCall call,
    ) async {
      setScreen(tester, const Size(420, 900));
      await tester.pumpWidget(
        inspectorApp(session, CallDetailPage(callId: call.id)),
      );
      await settle(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
    }

    testWidgets('offers to mock its response and to break on it', (
      tester,
    ) async {
      final call = makeCall(
        1,
        url: 'https://api.test/items/9',
        responseBody: '{}',
      );
      final session = _session(calls: [call]);
      await openDetail(tester, session, call);

      expect(find.text('Mock this response'), findsOneWidget);
      expect(find.text('Break on requests like this'), findsOneWidget);
    });

    testWidgets('starts a mock from it', (tester) async {
      final call = makeCall(
        1,
        url: 'https://api.test/items/9',
        status: 404,
        responseBody: '{"gone":true}',
      );
      final session = _session(calls: [call]);
      await openDetail(tester, session, call);

      await tester.tap(find.text('Mock this response'));
      await settle(tester);

      expect(find.byType(RuleEditorPage), findsOneWidget);
      expect(find.text('404'), findsOneWidget);
      expect(find.textContaining('"gone": true'), findsOneWidget);
    });

    testWidgets('starts a breakpoint from it', (tester) async {
      final call = makeCall(
        1,
        method: 'DELETE',
        url: 'https://api.test/items/9',
      );
      final session = _session(calls: [call]);
      await openDetail(tester, session, call);

      await tester.tap(find.text('Break on requests like this'));
      await settle(tester);

      expect(find.byType(RuleEditorPage), findsOneWidget);
      expect(find.text('api.test/items/9'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);
    });

    testWidgets('offers no mock of a call that got no response', (
      tester,
    ) async {
      final call = makeCall(
        1,
        status: null,
        state: FlutwireCallState.failed,
        error: const FlutwireError(type: 'SocketException', message: 'no'),
      );
      final session = _session(calls: [call]);
      await openDetail(tester, session, call);

      expect(find.text('Mock this response'), findsNothing);
      expect(find.text('Break on requests like this'), findsOneWidget);
    });

    testWidgets('offers neither where the rules are off', (tester) async {
      final call = makeCall(1, responseBody: '{}');
      await openDetail(tester, FakeSession(calls: [call]), call);

      expect(find.text('Mock this response'), findsNothing);
      expect(find.text('Break on requests like this'), findsNothing);
    });

    testWidgets('offers neither for what did not go through dart:io', (
      tester,
    ) async {
      final call = makeCall(1, source: FlutwireSource.dio, responseBody: '{}');
      await openDetail(tester, _session(calls: [call]), call);

      expect(find.text('Mock this response'), findsNothing);
      expect(find.text('Break on requests like this'), findsNothing);
    });
  });

  group('a call a rule touched', () {
    testWidgets('is marked in the list', (tester) async {
      final session = _session(
        calls: [
          makeCall(3).copyWith(intercept: FlutwireIntercept.mocked),
          makeCall(2).copyWith(intercept: FlutwireIntercept.edited),
          makeCall(1).copyWith(intercept: FlutwireIntercept.held),
        ],
      );
      await _openInspector(tester, session);

      expect(find.text('MOCK'), findsOneWidget);
      expect(find.text('EDITED'), findsOneWidget);
      expect(find.text('HELD'), findsOneWidget);
    });

    testWidgets('says what happened to it in its overview', (tester) async {
      final call = makeCall(1).copyWith(intercept: FlutwireIntercept.mocked);
      setScreen(tester, const Size(420, 900));
      await tester.pumpWidget(
        inspectorApp(
          FakeSession(calls: [call]),
          CallDetailPage(callId: call.id),
        ),
      );
      await settle(tester);

      expect(find.text('Intercepted'), findsOneWidget);
      expect(
        find.text('Answered by a mock rule, and nothing was sent'),
        findsOneWidget,
      );
    });
  });
}
