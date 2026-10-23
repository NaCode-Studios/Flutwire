import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/session.dart';
import 'package:flutwire/src/ui/shell.dart';

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

/// An app with [home] dressed as the inspector, working on [session].
Widget inspectorApp(FlutwireSession session, Widget home) => MaterialApp(
  home: FlutwireShell(session: session, child: home),
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
