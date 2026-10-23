import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/inspector/inspector_page.dart';
import 'package:flutwire/src/ui/widgets/chip.dart';

import 'calls.dart';

List<FlutwireCall> sample() => [
  makeCall(
    4,
    method: 'POST',
    url: 'https://api.test/login',
    status: 401,
    millis: 90,
    responseBody: '{"error":"bad password"}',
  ),
  makeCall(3, url: 'https://api.test/items/9', status: 200, millis: 3400),
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

Future<void> open(WidgetTester tester, {Size? size}) async {
  setScreen(tester, size ?? const Size(420, 900));
  await startFlutwire(tester, calls: sample());
  await tester.pumpWidget(inspectorApp(const InspectorPage()));
  await settle(tester);
}

void main() {
  tearDown(stopFlutwire);

  group('the list', () {
    testWidgets('says there is nothing yet', (tester) async {
      setScreen(tester, const Size(420, 900));
      await startFlutwire(tester);
      await tester.pumpWidget(inspectorApp(const InspectorPage()));
      await settle(tester);

      expect(find.text('Network activity'), findsOneWidget);
      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('lists every call with its status, path and host', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('/login'), findsOneWidget);
      expect(find.text('/items/9'), findsOneWidget);
      expect(find.text('/files/7'), findsOneWidget);
      expect(find.text('/boom'), findsOneWidget);
      expect(find.text('401'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('ERR'), findsOneWidget);
      expect(find.text('SocketException'), findsOneWidget);
    });

    testWidgets('puts the newest call on top', (tester) async {
      await open(tester);

      final login = tester.getTopLeft(find.text('/login')).dy;
      final boom = tester.getTopLeft(find.text('/boom')).dy;
      expect(login, lessThan(boom));
    });

    testWidgets('counts the calls and the failures', (tester) async {
      await open(tester);

      expect(find.text('CALLS'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      // 4 calls, of which the 401, the 500 and the exception went wrong.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a tap opens the call on a phone', (tester) async {
      await open(tester);

      await tester.tap(find.text('/items/9'));
      await settle(tester);

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('https://api.test/items/9'), findsOneWidget);
    });

    testWidgets('on a wide screen the call opens beside the list', (
      tester,
    ) async {
      await open(tester, size: const Size(1200, 800));
      expect(find.text('Pick a call to read it'), findsOneWidget);

      await tester.tap(find.text('/items/9'));
      await settle(tester);

      expect(find.text('Pick a call to read it'), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      // The list is still there.
      expect(find.text('/login'), findsOneWidget);
    });
  });

  group('search and filters', () {
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 200));
      await settle(tester);
    }

    testWidgets('search narrows the list', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Search'));
      await settle(tester);

      await type(tester, 'login');

      expect(find.text('/login'), findsOneWidget);
      expect(find.text('/items/9'), findsNothing);
    });

    testWidgets(
      'search says when nothing matches, and Clear filters resets it',
      (tester) async {
        await open(tester);
        await tester.tap(find.byTooltip('Search'));
        await settle(tester);

        await type(tester, 'zzzz');
        expect(find.text('No call matches'), findsOneWidget);

        await tester.tap(find.text('Clear filters'));
        await settle(tester);
        expect(find.text('/login'), findsOneWidget);
        expect(find.text('No call matches'), findsNothing);
      },
    );

    testWidgets('search finds text inside a body', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Search'));
      await settle(tester);

      await type(tester, 'bad password');
      // Bodies are read in the background, a few at a time.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);

      expect(find.text('/login'), findsOneWidget);
      expect(find.text('/items/9'), findsNothing);
    });

    testWidgets('a method chip narrows the list', (tester) async {
      await open(tester);

      await tester.tap(find.widgetWithText(FwChip, 'DELETE'));
      await settle(tester);

      expect(find.text('/files/7'), findsOneWidget);
      expect(find.text('/login'), findsNothing);
    });

    testWidgets('a state chip narrows the list', (tester) async {
      await open(tester);

      // The chip row scrolls sideways; the 5xx chip starts off screen.
      final chip = find.widgetWithText(FwChip, '5xx');
      await tester.scrollUntilVisible(
        chip,
        150,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.horizontal,
        ),
      );
      await tester.tap(chip);
      await settle(tester);

      expect(find.text('/files/7'), findsOneWidget);
      expect(find.text('/items/9'), findsNothing);
    });
  });

  group('selection', () {
    testWidgets('a long press selects, and select all takes the rest', (
      tester,
    ) async {
      await open(tester);

      await tester.longPress(find.text('/login'));
      await settle(tester);
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Select all'));
      await settle(tester);
      expect(find.text('4 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Network activity'), findsOneWidget);
    });

    testWidgets('delete asks first, then removes the selected calls', (
      tester,
    ) async {
      await open(tester);
      await tester.longPress(find.text('/login'));
      await settle(tester);

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      expect(find.text('Delete the selected calls?'), findsOneWidget);

      await tester.tap(find.text('Delete').last);
      await settle(tester, 1000);

      expect(find.text('/login'), findsNothing);
      expect(find.text('/items/9'), findsOneWidget);
    });

    testWidgets('cancelling the question keeps the calls', (tester) async {
      await open(tester);
      await tester.longPress(find.text('/login'));
      await settle(tester);

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.text('/login'), findsOneWidget);
    });

    testWidgets('pinning keeps the call pinned in the history', (tester) async {
      await open(tester);
      await tester.longPress(find.text('/login'));
      await settle(tester);

      await tester.tap(find.byTooltip('Pin'));
      await settle(tester);

      expect(Flutwire.store!.find(4)!.pinned, isTrue);
    });
  });

  group('the menu and the recording row', () {
    testWidgets('pausing from the row stops the recording', (tester) async {
      await open(tester);
      expect(find.text('RECORDING'), findsOneWidget);

      await tester.tap(find.text('RECORDING'));
      await settle(tester);

      expect(Flutwire.isPaused, isTrue);
      expect(find.text('PAUSED'), findsOneWidget);
    });

    testWidgets('clearing the history asks first', (tester) async {
      await open(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Clear history'));
      await settle(tester);
      expect(find.text('Clear the history?'), findsOneWidget);

      await tester.tap(find.text('Clear history').last);
      await settle(tester, 1000);

      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('sorting by the slowest puts it first', (tester) async {
      await open(tester);

      await tester.tap(find.text('Newest first'));
      await settle(tester);
      await tester.tap(find.text('Slowest first').last);
      await settle(tester);

      final slowest = tester.getTopLeft(find.text('/items/9')).dy;
      final newest = tester.getTopLeft(find.text('/login')).dy;
      expect(slowest, lessThan(newest));
    });

    testWidgets('settings open as a sheet', (tester) async {
      await open(tester);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);

      expect(find.text('APPEARANCE'), findsOneWidget);
    });
  });
}
