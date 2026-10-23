import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/inspector_launcher.dart';

import 'calls.dart';
import 'fake_session.dart';

const _inspector = 'Network activity';

Widget _app({GlobalKey<NavigatorState>? key}) => MaterialApp(
  navigatorKey: key,
  home: const Scaffold(body: Text('the app')),
);

void main() {
  late FakeSession session;
  late GlobalKey<NavigatorState> key;
  late InspectorLauncher launcher;

  setUp(() {
    session = FakeSession();
    key = GlobalKey<NavigatorState>();
    launcher = InspectorLauncher(key);
  });

  tearDown(() => launcher.dispose());

  testWidgets('opens the inspector on the navigator of the key', (
    tester,
  ) async {
    await tester.pumpWidget(_app(key: key));

    final opened = launcher.open(session);
    await settle(tester);

    expect(find.text(_inspector), findsOneWidget);
    expect(launcher.isOpen.value, isTrue);

    key.currentState!.pop();
    await settle(tester);
    await opened;
    expect(launcher.isOpen.value, isFalse);
  });

  testWidgets('finds the navigator itself when the app gave no key', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    final opened = launcher.open(session);
    await settle(tester);

    expect(find.text(_inspector), findsOneWidget);
    Navigator.of(tester.element(find.text(_inspector))).pop();
    await settle(tester);
    await opened;
  });

  testWidgets('uses the navigator above a context when given one', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    final opened = launcher.open(session, tester.element(find.text('the app')));
    await settle(tester);

    expect(find.text(_inspector), findsOneWidget);
    Navigator.of(tester.element(find.text(_inspector))).pop();
    await settle(tester);
    await opened;
  });

  testWidgets('opens only one inspector at a time', (tester) async {
    await tester.pumpWidget(_app(key: key));

    final first = launcher.open(session);
    await launcher.open(session);
    await settle(tester);

    expect(find.text(_inspector), findsOneWidget);
    key.currentState!.pop();
    await settle(tester);
    await first;
  });

  testWidgets('does nothing when there is no navigator', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await launcher.open(session);

    expect(launcher.isOpen.value, isFalse);
  });

  group('waiting for the first screen', () {
    testWidgets('opens as soon as the app has a navigator', (tester) async {
      launcher.openWhenReady(session);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(_inspector), findsNothing);

      await tester.pumpWidget(_app(key: key));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(find.text(_inspector), findsOneWidget);
    });

    testWidgets('gives up after a while', (tester) async {
      launcher.openWhenReady(session);
      await tester.pump(const Duration(seconds: 20));

      await tester.pumpWidget(_app(key: key));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(_inspector), findsNothing);
    });
  });
}
