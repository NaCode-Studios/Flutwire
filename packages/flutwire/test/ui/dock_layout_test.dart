import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/dock.dart';
import 'package:flutwire/src/ui/dock/dock_layout.dart';
import 'package:flutwire/src/ui/inspector/inspector_page.dart';
import 'package:flutwire/src/ui/inspector_launcher.dart';
import 'package:flutwire/src/ui/shell.dart';

import 'calls.dart';
import 'fake_session.dart';

const _wide = Size(1200, 800);
const _phone = Size(420, 900);
const _inspector = 'Network activity';
const _handle = ValueKey('flutwire.dock.handle');

/// An app that counts its taps and says how big it believes the screen is.
class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: Column(
        children: [
          Text('app ${size.width.round()}x${size.height.round()}'),
          TextButton(
            onPressed: () => setState(() => taps++),
            child: Text('taps $taps'),
          ),
        ],
      ),
    );
  }
}

Future<FakeSession> pumpDock(
  WidgetTester tester, {
  Size size = _phone,
  FakeSession? session,
}) async {
  setScreen(tester, size);
  final used =
      session ??
      FakeSession(
        calls: [
          makeCall(2, url: 'https://api.test/items'),
          makeCall(1, url: 'https://api.test/login', method: 'POST'),
        ],
      );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => DockLayout(session: used, app: child!),
      home: const _App(),
    ),
  );
  await settle(tester);
  return used;
}

Future<void> openDock(WidgetTester tester, FakeSession session) async {
  session.dock.open();
  await settle(tester);
}

Future<void> chooseFromMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await settle(tester);
  await tester.tap(find.text(item));
  await settle(tester);
}

void main() {
  testWidgets('leaves the app alone while the dock is closed', (tester) async {
    await pumpDock(tester);

    expect(find.text('app 420x900'), findsOneWidget);
    expect(find.text(_inspector), findsNothing);
  });

  testWidgets('puts the inspector to the right of the app on a wide screen', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);

    await openDock(tester, session);

    // 42 per cent of the width is the panel, 16 points are the handle.
    expect(find.text('app 680x800'), findsOneWidget);
    expect(find.text(_inspector), findsOneWidget);
    expect(tester.getTopLeft(find.text(_inspector)).dx, greaterThan(680));
  });

  testWidgets('puts it under the app on a narrow one', (tester) async {
    final session = await pumpDock(tester);

    await openDock(tester, session);

    expect(find.text('app 420x506'), findsOneWidget);
    expect(find.text(_inspector), findsOneWidget);
    expect(tester.getTopLeft(find.text(_inspector)).dy, greaterThan(506));
  });

  testWidgets('shows the calls in the panel', (tester) async {
    final session = await pumpDock(tester, size: _wide);

    await openDock(tester, session);

    expect(find.text('/items'), findsOneWidget);
    expect(find.text('/login'), findsOneWidget);
  });

  testWidgets('does not rebuild the app when the inspector docks', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    await tester.tap(find.text('taps 1'));
    await tester.pump();
    expect(find.text('taps 2'), findsOneWidget);

    await openDock(tester, session);
    expect(find.text('taps 2'), findsOneWidget);

    session.dock.close();
    await settle(tester);
    expect(find.text('taps 2'), findsOneWidget);
    expect(find.text('app 1200x800'), findsOneWidget);
  });

  testWidgets('is resized by dragging the strip between the two', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await tester.drag(find.byKey(_handle), const Offset(-100, 0));
    await settle(tester);

    // A drag to the left gives the panel what the app gives up.
    final app = RegExp(r'app (\d+)x800');
    final width = int.parse(
      app
          .firstMatch(
            tester
                .widgetList<Text>(find.textContaining('app '))
                .map((t) => t.data!)
                .firstWhere(app.hasMatch),
          )!
          .group(1)!,
    );
    expect(width, inInclusiveRange(550, 600));
    expect(session.dock.extent, greaterThan(0.48));
  });

  testWidgets('keeps the size it was dragged to', (tester) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await tester.drag(find.byKey(_handle), const Offset(-100, 0));
    await settle(tester);

    expect(session.store.preferences.read('dockExtent'), isNotNull);
    expect(session.store.preferences.read('dockMode'), 'docked');
  });

  testWidgets('never takes more than the app can spare', (tester) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await tester.drag(find.byKey(_handle), const Offset(-2000, 0));
    await settle(tester);

    expect(session.dock.extent, FlutwireDock.maxExtent);
    expect(find.text('app 224x800'), findsOneWidget);
  });

  testWidgets('moves to the other side from its menu', (tester) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await chooseFromMenu(tester, 'Move to the bottom');

    expect(find.text('app 1200x448'), findsOneWidget);
    expect(session.store.preferences.read('dockSide'), 'bottom');

    await chooseFromMenu(tester, 'Move to the right');
    expect(find.text('app 680x800'), findsOneWidget);
  });

  testWidgets('closes with the button in its top bar', (tester) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    expect(find.text(_inspector), findsNothing);
    expect(find.text('app 1200x800'), findsOneWidget);
    expect(session.dock.isOpen, isFalse);
    // It opens docked again next time.
    expect(session.dock.prefersDock, isTrue);
  });

  testWidgets('goes full screen from its menu, and stays there', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await chooseFromMenu(tester, 'Open full screen');

    expect(session.dock.isOpen, isFalse);
    expect(session.dock.prefersDock, isFalse);
    expect(session.inspectorOpened, 1);
  });

  testWidgets('opens a call inside the panel, and Back stays there', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);

    await tester.tap(find.text('/login'));
    await settle(tester);

    expect(find.text('POST  api.test'), findsOneWidget);
    expect(find.text('app 680x800'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text(_inspector), findsOneWidget);
    expect(find.text('taps 0'), findsOneWidget);
  });

  testWidgets('the inspector on the screen offers to dock', (tester) async {
    final session = FakeSession(calls: [makeCall(1)]);
    setScreen(tester, _phone);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DockLayout(session: session, app: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  shellRoute(
                    session,
                    name: 'test',
                    child: const InspectorPage(),
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
    expect(find.text(_inspector), findsOneWidget);

    await chooseFromMenu(tester, 'Dock beside the app');

    // The route is gone, and the same inspector is in the panel.
    expect(find.text('open'), findsOneWidget);
    expect(find.text(_inspector), findsOneWidget);
    expect(session.dock.isOpen, isTrue);
  });

  testWidgets('no dock is offered where there is nothing to dock into', (
    tester,
  ) async {
    setScreen(tester, _phone);
    final session = FakeSession(calls: [makeCall(1)]);
    await tester.pumpWidget(inspectorApp(session, const InspectorPage()));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester);

    expect(find.text('Dock beside the app'), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('the launcher opens it docked when it was left docked', (
    tester,
  ) async {
    final session = await pumpDock(tester, size: _wide);
    session.dock.open();
    session.dock.close();
    await settle(tester);
    final key = GlobalKey<NavigatorState>();
    final launcher = InspectorLauncher(key);
    addTearDown(launcher.dispose);

    await launcher.open(session);
    await settle(tester);

    expect(session.dock.isOpen, isTrue);
    expect(find.text(_inspector), findsOneWidget);
    expect(launcher.isOpen.value, isFalse);
  });

  testWidgets('the launcher does not open a second inspector', (tester) async {
    final session = await pumpDock(tester, size: _wide);
    await openDock(tester, session);
    final launcher = InspectorLauncher(GlobalKey<NavigatorState>());
    addTearDown(launcher.dispose);

    await launcher.open(session);
    await settle(tester);

    expect(find.text(_inspector), findsOneWidget);
  });

  testWidgets('fits in the narrowest panel, in either language', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('it')]) {
      final session = FakeSession(
        config: FlutwireConfig(
          enabled: true,
          captureDartIo: false,
          persist: false,
          shortcut: false,
          locale: locale,
          notification: const FlutwireNotificationConfig(enabled: false),
        ),
        calls: [makeCall(1, url: 'https://api.test/a/rather/long/path?x=1')],
      );
      await pumpDock(tester, size: const Size(900, 700), session: session);
      session.dock.resizeBy(-1);
      await openDock(tester, session);

      // The panel is at its least, 280 points wide, and nothing overflows.
      expect(find.text('app 604x700'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
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
      calls: [makeCall(1)],
    );
    await pumpDock(tester, size: _wide, session: session);
    await openDock(tester, session);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester);

    expect(find.text('Apri a schermo intero'), findsOneWidget);
    expect(find.text('Sposta in basso'), findsOneWidget);
  });
}
