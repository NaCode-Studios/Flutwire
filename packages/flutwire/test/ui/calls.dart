import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/shell.dart';

const nativeChannel = MethodChannel('it.nacodestudios.flutwire/native');

FlutwireBody jsonBody(String text) => FlutwireBody(
  bytes: Uint8List.fromList(utf8.encode(text)),
  contentType: 'application/json',
);

/// A finished call, or a running or failed one, with the parts a test needs.
FlutwireCall makeCall(
  int id, {
  String method = 'GET',
  String url = 'https://api.test/items',
  int? status = 200,
  FlutwireCallState state = FlutwireCallState.completed,
  int millis = 120,
  String? requestBody,
  String? responseBody,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  FlutwireError? error,
  FlutwireGraphql? graphql,
  bool pinned = false,
}) {
  final start = DateTime.utc(2026, 10, 23, 12);
  final pending = state == FlutwireCallState.pending;
  return FlutwireCall(
    id: id,
    method: method,
    uri: Uri.parse(url),
    source: FlutwireSource.io,
    state: state,
    startedAt: start,
    firstByteAt: pending || status == null
        ? null
        : start.add(Duration(milliseconds: millis ~/ 2)),
    endedAt: pending ? null : start.add(Duration(milliseconds: millis)),
    pinned: pinned,
    error: error,
    graphql: graphql,
    request: FlutwireRequest(
      headers: FlutwireHeaders.fromMap(requestHeaders),
      body: requestBody == null ? FlutwireBody.empty() : jsonBody(requestBody),
    ),
    response: status == null || pending
        ? null
        : FlutwireResponse(
            statusCode: status,
            reasonPhrase: status == 200 ? 'OK' : '',
            headers: FlutwireHeaders.fromMap(responseHeaders),
            body: responseBody == null
                ? FlutwireBody.empty()
                : jsonBody(responseBody),
          ),
  );
}

/// Starts Flutwire the way an app does, with the native half absent.
Future<void> startFlutwire(
  WidgetTester tester, {
  List<FlutwireCall> calls = const [],
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeChannel, (_) async => null);
  await tester.runAsync(
    () => Flutwire.init(
      config: const FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: Locale('en'),
        themeMode: ThemeMode.dark,
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    ),
  );
  final store = Flutwire.store! as MemoryFlutwireStore;
  // Oldest first, so the newest ends up on top.
  for (final call in calls.reversed) {
    store.put(call);
  }
  store.flush();
}

Future<void> stopFlutwire() async {
  await Flutwire.reset();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(nativeChannel, null);
}

/// An app with [home] dressed as the inspector.
Widget inspectorApp(Widget home) => MaterialApp(
  navigatorKey: Flutwire.navigatorKey,
  home: FlutwireShell(child: home),
);

/// The inspector pulses while it records, so `pumpAndSettle` never settles:
/// this lets the animations and the short timers run instead.
Future<void> settle(WidgetTester tester, [int milliseconds = 500]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: milliseconds));
}

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}
