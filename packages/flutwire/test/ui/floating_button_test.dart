import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

const _channel = MethodChannel('it.nacodestudios.flutwire/native');

FlutwireConfig config({
  FlutwireButtonMode mode = FlutwireButtonMode.always,
  bool notification = false,
}) => FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  floatingButton: mode,
  notification: FlutwireNotificationConfig(enabled: notification),
);

Future<void> pumpApp(WidgetTester tester, FlutwireConfig config) async {
  await tester.runAsync(() => Flutwire.init(config: config));
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: Flutwire.navigatorKey,
      builder: Flutwire.builder,
      home: const Scaffold(body: Center(child: Text('the app'))),
    ),
  );
  await tester.pump();
}

final button = find.byKey(const ValueKey('flutwire.button'));

/// The inspector pulses while it records, so `pumpAndSettle` never settles.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void recordCall({int status = 200}) {
  final recorder = Flutwire.begin(
    method: 'GET',
    uri: Uri.parse('https://api.test/items'),
    source: FlutwireSource.custom,
  )!;
  recorder
    ..requestSent()
    ..responseHead(statusCode: status, headers: FlutwireHeaders.empty)
    ..complete();
  (Flutwire.store! as MemoryFlutwireStore).flush();
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async => null);
  });

  tearDown(() async {
    await Flutwire.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('shows the app, and a button with the number of calls', (
    tester,
  ) async {
    await pumpApp(tester, config());

    expect(find.text('the app'), findsOneWidget);
    expect(button, findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    recordCall();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('marks a failed call with a red dot', (tester) async {
    await pumpApp(tester, config());
    recordCall(status: 500);
    await tester.pump();

    final dots = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(dots, findsOneWidget);
  });

  testWidgets('never shows the button when told not to', (tester) async {
    await pumpApp(tester, config(mode: FlutwireButtonMode.never));
    expect(button, findsNothing);
  });

  group('by default', () {
    testWidgets('shows where there is no notification to open', (tester) async {
      await pumpApp(tester, config(mode: FlutwireButtonMode.auto));
      expect(button, findsOneWidget);
    });

    testWidgets('stays away where the notification is turned on', (
      tester,
    ) async {
      // A native half that answers means a notification exists.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'initialize') {
              return {
                'permission': 'granted',
                'storagePath': null,
                'temporaryPath': null,
              };
            }
            return null;
          });
      await pumpApp(
        tester,
        config(mode: FlutwireButtonMode.auto, notification: true),
      );
      expect(button, findsNothing);
    });
  });

  testWidgets('tapping it opens the inspector, and it steps aside', (
    tester,
  ) async {
    await pumpApp(tester, config());

    await tester.tap(button);
    await settle(tester);

    expect(find.text('Network activity'), findsOneWidget);
    expect(button, findsNothing);
  });

  testWidgets('Ctrl+Shift+L opens the inspector even without the button', (
    tester,
  ) async {
    await pumpApp(tester, config(mode: FlutwireButtonMode.never));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(find.text('Network activity'), findsOneWidget);
  });

  testWidgets('a plain L does nothing', (tester) async {
    await pumpApp(tester, config(mode: FlutwireButtonMode.never));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await settle(tester);

    expect(find.text('Network activity'), findsNothing);
  });

  testWidgets('can be dragged', (tester) async {
    await pumpApp(tester, config());
    final before = tester.getTopLeft(button);

    await tester.drag(button, const Offset(-80, -120));
    await tester.pump();

    final after = tester.getTopLeft(button);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
  });

  testWidgets('does nothing while Flutwire is not recording', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: Flutwire.builder,
        home: const Scaffold(body: Text('the app')),
      ),
    );
    expect(find.text('the app'), findsOneWidget);
    expect(button, findsNothing);
  });
}
