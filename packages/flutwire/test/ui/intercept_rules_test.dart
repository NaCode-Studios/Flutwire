import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/interception.dart';
import 'package:flutwire/src/intercept/rule.dart';
import 'package:flutwire/src/ui/intercept/rule_editor_page.dart';
import 'package:flutwire/src/ui/intercept/rules_page.dart';

import 'body/helpers.dart' show spyOnClipboard;
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

/// A session with the rules turned on, which is what a test that is about them
/// needs.
FakeSession _session({List<FlutwireCall> calls = const []}) {
  final session = FakeSession(config: _on, calls: calls);
  session.interception = FlutwireInterception(session.store.preferences);
  return session;
}

FlutwireRule _mock(
  FlutwireInterception interception,
  String pattern, {
  int status = 200,
  String body = '',
  String name = '',
  String? method,
  bool enabled = true,
}) {
  final rule = FlutwireRule(
    id: interception.rules.newId(),
    kind: FlutwireRuleKind.mock,
    pattern: pattern,
    method: method,
    name: name,
    enabled: enabled,
    response: FlutwireMockResponse(
      statusCode: status,
      body: Uint8List.fromList(utf8.encode(body)),
    ),
  );
  interception.rules.add(rule);
  return rule;
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

Future<void> _openRules(WidgetTester tester, FakeSession session) async {
  setScreen(tester, const Size(420, 900));
  await tester.pumpWidget(inspectorApp(session, const RulesPage()));
  await settle(tester);
}

Future<void> _openEditor(
  WidgetTester tester,
  FakeSession session, {
  required FlutwireRuleKind kind,
  FlutwireRule? rule,
  FlutwireCall? from,
}) async {
  setScreen(tester, const Size(420, 1400));
  await tester.pumpWidget(
    inspectorApp(session, RuleEditorPage(kind: kind, rule: rule, from: from)),
  );
  await settle(tester);
}

void main() {
  group('the page of rules', () {
    testWidgets('says that the rules are off until the app turns them on', (
      tester,
    ) async {
      final spy = spyOnClipboard(tester);
      await _openRules(tester, FakeSession());

      expect(find.text('Mocks and breakpoints'), findsOneWidget);
      expect(
        find.textContaining('change what the app sends and receives'),
        findsOneWidget,
      );
      expect(find.textContaining('interception: true'), findsOneWidget);
      expect(find.text('New mock'), findsNothing);

      await tester.tap(find.textContaining('interception: true'));
      await settle(tester);
      expect(spy.copied.single, contains('FlutwireConfig(interception: true)'));
    });

    testWidgets('says why they are not here, when the app asked for them', (
      tester,
    ) async {
      await _openRules(tester, FakeSession(config: _on));

      expect(find.textContaining('dart:io capture'), findsOneWidget);
      expect(find.textContaining('interception: true'), findsNothing);
    });

    testWidgets('says what to do when there is no rule', (tester) async {
      await _openRules(tester, _session());

      expect(find.text('No rules yet'), findsOneWidget);
      expect(find.text('New mock'), findsOneWidget);
      expect(find.text('New breakpoint'), findsOneWidget);
    });

    testWidgets('lists the rules, the newest first', (tester) async {
      final session = _session();
      final interception = session.interception!;
      _mock(interception, 'api.test/old/*', name: 'Old');
      _breakpoint(interception, 'api.test/new/*');
      await _openRules(tester, session);

      expect(find.text('ANY api.test/new/*'), findsOneWidget);
      expect(find.text('Old'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('ANY api.test/new/*')).dy,
        lessThan(tester.getTopLeft(find.text('Old')).dy),
      );
      expect(find.text('Breakpoint'), findsOneWidget);
      expect(find.textContaining('Mock  ·  200'), findsOneWidget);
    });

    testWidgets('turns a rule off and on from its switch', (tester) async {
      final session = _session();
      final rule = _mock(session.interception!, 'api.test/*');
      await _openRules(tester, session);

      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(session.interception!.rules.find(rule.id)!.enabled, isFalse);

      await tester.tap(find.byType(Switch));
      await settle(tester);
      expect(session.interception!.rules.find(rule.id)!.enabled, isTrue);
    });

    testWidgets('opens a rule in its editor', (tester) async {
      final session = _session();
      _mock(session.interception!, 'api.test/items/*', name: 'Items');
      await _openRules(tester, session);

      await tester.tap(find.text('Items'));
      await settle(tester);

      expect(find.byType(RuleEditorPage), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == 'api.test/items/*',
        ),
        findsOneWidget,
      );
    });

    testWidgets('makes a rule from nothing', (tester) async {
      final session = _session();
      await _openRules(tester, session);

      await tester.tap(find.text('New breakpoint'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, '').at(1),
        'api.test/login',
      );
      await tester.tap(find.text('Save'));
      await settle(tester);

      final rule = session.interception!.rules.all.single;
      expect(rule.kind, FlutwireRuleKind.breakpoint);
      expect(rule.pattern, 'api.test/login');
      expect(rule.method, isNull);
      expect(find.text('ANY api.test/login'), findsOneWidget);
    });
  });

  group('the editor of a rule', () {
    testWidgets('starts a breakpoint from a call', (tester) async {
      final session = _session();
      final call = makeCall(
        1,
        method: 'POST',
        url: 'https://api.test/items/9?x=1',
      );
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.breakpoint,
        from: call,
      );

      expect(find.text('api.test/items/9?*'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await settle(tester);

      final rule = session.interception!.rules.all.single;
      expect(rule.kind, FlutwireRuleKind.breakpoint);
      expect(rule.pattern, 'api.test/items/9?*');
      expect(rule.method, 'POST');
      expect(rule.matches('POST', call.uri), isTrue);
    });

    testWidgets('starts a mock from the response of a call', (tester) async {
      final session = _session();
      final call = makeCall(
        1,
        url: 'https://api.test:8443/items',
        status: 201,
        responseBody: '{"id":1}',
        responseHeaders: {
          'content-type': 'application/json',
          'content-length': '999',
          'content-encoding': 'gzip',
          'x-kept': 'yes',
        },
      );
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.mock,
        from: call,
      );

      expect(find.text('api.test:8443/items'), findsOneWidget);
      expect(find.text('201'), findsOneWidget);
      // The body is laid out for editing, and the fields about its encoding
      // are not offered, because the body is served as it is.
      expect(find.textContaining('"id": 1'), findsOneWidget);
      expect(find.text('x-kept'), findsOneWidget);
      expect(find.text('content-length'), findsNothing);
      expect(find.text('content-encoding'), findsNothing);

      await tester.tap(find.text('Save'));
      await settle(tester);

      final rule = session.interception!.rules.all.single;
      expect(rule.kind, FlutwireRuleKind.mock);
      final response = rule.response!;
      expect(response.statusCode, 201);
      expect(response.headers.first('x-kept'), 'yes');
      expect(response.headers.contains('content-length'), isFalse);
      expect(jsonDecode(utf8.decode(response.body)), {'id': 1});
    });

    testWidgets('changes what a mock says', (tester) async {
      final session = _session();
      final rule = _mock(
        session.interception!,
        'api.test/*',
        status: 200,
        body: 'before',
      );
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.mock,
        rule: rule,
      );

      await tester.enterText(find.widgetWithText(TextField, '200'), '503');
      await tester.enterText(find.widgetWithText(TextField, 'before'), 'after');
      await tester.tap(find.text('Save'));
      await settle(tester);

      final saved = session.interception!.rules.find(rule.id)!;
      expect(saved.response!.statusCode, 503);
      expect(utf8.decode(saved.response!.body), 'after');
      expect(session.interception!.rules.all, hasLength(1));
    });

    testWidgets('does not save a rule that says nothing about what it is for', (
      tester,
    ) async {
      final session = _session();
      await _openEditor(tester, session, kind: FlutwireRuleKind.breakpoint);

      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Write what the address looks like.'), findsOneWidget);
      expect(session.interception!.rules.all, isEmpty);
      expect(find.byType(RuleEditorPage), findsOneWidget);
    });

    testWidgets('does not save a status that is not one', (tester) async {
      final session = _session();
      await _openEditor(tester, session, kind: FlutwireRuleKind.mock);
      await tester.enterText(find.widgetWithText(TextField, '200'), '99');
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'api.test/items/*',
        ),
        'api.test/*',
      );

      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(
        find.text('A status is a number from 100 to 599.'),
        findsOneWidget,
      );
      expect(session.interception!.rules.all, isEmpty);
    });

    testWidgets('keeps a body that is not text as it was recorded', (
      tester,
    ) async {
      final session = _session();
      final bytes = Uint8List.fromList([0, 1, 2, 3, 255]);
      final call = makeCall(1, status: 200).copyWith(
        response: FlutwireResponse(
          statusCode: 200,
          headers: FlutwireHeaders.fromMap({
            'content-type': 'application/octet-stream',
          }),
          body: FlutwireBody(
            bytes: bytes,
            contentType: 'application/octet-stream',
          ),
        ),
      );
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.mock,
        from: call,
      );

      expect(
        find.text(
          'The stored body is not text, so it is served as it was recorded.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(session.interception!.rules.all.single.response!.body, bytes);
    });

    testWidgets('says when the recorded body was cut', (tester) async {
      final session = _session();
      final call = makeCall(1).copyWith(
        response: FlutwireResponse(
          statusCode: 200,
          headers: FlutwireHeaders.empty,
          body: FlutwireBody(
            bytes: Uint8List.fromList(utf8.encode('{"a":1')),
            totalBytes: 4096,
            contentType: 'application/json',
          ),
        ),
      );
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.mock,
        from: call,
      );

      expect(
        find.textContaining('The body was cut at 6 B of 4.0 KB'),
        findsOneWidget,
      );
    });

    testWidgets('deletes a rule, after asking', (tester) async {
      final session = _session();
      final rule = _mock(session.interception!, 'api.test/*', name: 'Doomed');
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.mock,
        rule: rule,
      );

      await tester.tap(find.byTooltip('Delete the rule'));
      await settle(tester);
      expect(find.text('Delete this rule?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(session.interception!.rules.all, hasLength(1));

      await tester.tap(find.byTooltip('Delete the rule'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);

      expect(session.interception!.rules.all, isEmpty);
    });

    testWidgets('changes the method a rule is about', (tester) async {
      final session = _session();
      final rule = _breakpoint(session.interception!, 'api.test/*');
      await _openEditor(
        tester,
        session,
        kind: FlutwireRuleKind.breakpoint,
        rule: rule,
      );

      await tester.tap(find.byTooltip('Method'));
      await settle(tester);
      await tester.tap(find.text('DELETE'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(session.interception!.rules.find(rule.id)!.method, 'DELETE');
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
      );
      session.interception = FlutwireInterception(session.store.preferences);
      await _openRules(tester, session);

      expect(find.text('Mock e breakpoint'), findsOneWidget);
      expect(find.text('Ancora nessuna regola'), findsOneWidget);
      expect(find.text('Nuovo mock'), findsOneWidget);
    });
  });
}
