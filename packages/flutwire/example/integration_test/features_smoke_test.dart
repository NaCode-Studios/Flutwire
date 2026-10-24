// Runs what 0.2.0 added on the platform it is started on: a call made through
// dart:io is recorded, two calls are compared, the statistics add them up and
// the inspector docks beside the app. It goes through the public API and the
// real screens against a server on the loopback interface, so it needs a
// device or a desktop and no network:
//
//   flutter test integration_test/features_smoke_test.dart -d macos
//   flutter test integration_test/features_smoke_test.dart -d <simulator>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('records, compares, adds up and docks', (tester) async {
    // A wide screen, so the inspector has two panes and docks on the right.
    tester.view.physicalSize =
        const Size(1400, 900) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);

    await Flutwire.init(
      config: const FlutwireConfig(
        enabled: true,
        persist: false,
        shortcut: false,
        interception: true,
        locale: Locale('en'),
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final path = request.uri.path;
      await Future<void>.delayed(
        Duration(milliseconds: path == '/orders/2' ? 150 : 10),
      );
      final response = request.response;
      if (path == '/missing') {
        response
          ..statusCode = HttpStatus.notFound
          ..write('no such order');
      } else {
        response
          ..headers.contentType = ContentType.json
          ..write('{"path":"$path","items":[1,2,3]}');
      }
      await response.close();
    });

    Future<void> get(String path) async {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();
    }

    await get('/orders/1');
    await get('/orders/2');
    await get('/missing');

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: Flutwire.navigatorKey,
        builder: Flutwire.builder,
        home: const Scaffold(body: Center(child: Text('the app'))),
      ),
    );
    await settle(tester);

    // The calls went through dart:io and were recorded as they ended.
    final calls = Flutwire.calls.value;
    expect(
      [for (final c in calls) c.uri.path],
      ['/missing', '/orders/2', '/orders/1'],
    );
    expect([for (final c in calls) c.statusCode], [404, 200, 200]);
    expect(calls[1].response!.body.text, contains('/orders/2'));

    unawaited(Flutwire.open());
    await settle(tester);
    expect(find.text('Network activity'), findsOneWidget);

    // Two calls side by side.
    await tester.longPress(find.text('/orders/2'));
    await settle(tester, 5);
    await tester.tap(find.text('/orders/1'));
    await settle(tester, 5);
    await tester.tap(find.byTooltip('Compare'));
    await settle(tester);
    expect(find.text('Differences only'), findsOneWidget);
    expect(find.text('/orders/1'), findsWidgets);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    // The numbers of the history, and its timeline.
    await tester.tap(find.byTooltip('Statistics'));
    await settle(tester);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Error rate'.toUpperCase()), findsOneWidget);
    await tester.tap(find.text('Timeline'));
    await settle(tester);
    // The three calls ran one after the other.
    expect(find.text('One at a time'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    // Docked, the inspector sits to the right of the app, which stays.
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await settle(tester);
    await tester.tap(find.text('Dock beside the app'));
    await settle(tester);
    expect(find.text('the app'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Network activity')).dx,
      greaterThan(tester.getTopLeft(find.text('the app')).dx),
    );
    expect(tester.takeException(), isNull);
  });
}
