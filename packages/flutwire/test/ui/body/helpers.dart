import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/ui/body/body_viewer.dart';
import 'package:flutwire/src/ui/body/search.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

import '../harness.dart';

/// A one pixel PNG, to draw in tests.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// A body of [text] with the media type [type].
FlutwireBody textBody(String text, {String? type, int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(utf8.encode(text)),
  totalBytes: total,
  contentType: type,
);

/// A JSON body.
FlutwireBody jsonBody(String text, {int? total}) =>
    textBody(text, type: 'application/json', total: total);

/// A body of raw [bytes].
FlutwireBody bytesBody(List<int> bytes, {String? type, int? total}) =>
    FlutwireBody(
      bytes: Uint8List.fromList(bytes),
      totalBytes: total,
      contentType: type,
    );

/// A `multipart/form-data` body written by hand with the boundary `b`.
FlutwireBody multipartBody(List<String> lines, {int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(latin1.encode(lines.join('\r\n'))),
  totalBytes: total,
  contentType: 'multipart/form-data; boundary=b',
);

/// A call to hand to the viewer.
FlutwireCall testCall({int id = 7}) => FlutwireCall(
  id: id,
  method: 'POST',
  uri: Uri.parse('https://example.com/items'),
  source: FlutwireSource.io,
  startedAt: DateTime.utc(2026, 10, 23),
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
);

/// Pumps the viewer for [body] in the Flutwire theme.
Future<void> pumpViewer(
  WidgetTester tester,
  FlutwireBody body, {
  bool isRequest = false,
  List<FlutwireBodyDecoder> decoders = const [],
  FlutwireBodyActions actions = const FlutwireBodyActions(),
  FlutwireTokens tokens = FlutwireTokens.dark,
  Size size = const Size(400, 800),
}) {
  return pumpFlutwire(
    tester,
    FlutwireBodyViewer(
      call: testCall(),
      body: body,
      isRequest: isRequest,
      decoders: decoders,
      actions: actions,
    ),
    tokens: tokens,
    size: size,
  );
}

/// Records what the app puts on the clipboard.
class ClipboardSpy {
  /// Every text copied, oldest first.
  final List<String> copied = [];

  /// The last text copied, or null.
  String? get last => copied.isEmpty ? null : copied.last;
}

/// Replaces the platform clipboard with a spy for the length of the test.
ClipboardSpy spyOnClipboard(WidgetTester tester) {
  final spy = ClipboardSpy();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        spy.copied.add(args['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return spy;
}

/// The leaf spans of every paragraph on screen, offstage rows included.
Iterable<TextSpan> allLeafSpans(WidgetTester tester) sync* {
  for (final element in find.byType(RichText, skipOffstage: false).evaluate()) {
    final rich = element.widget as RichText;
    final out = <TextSpan>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) out.add(span);
      return true;
    });
    yield* out;
  }
}

/// The text drawn on a background of [color], one entry per span.
List<String> highlighted(WidgetTester tester, Color color) => [
  for (final span in allLeafSpans(tester))
    if (span.style?.backgroundColor == color) span.text!,
];

/// Types [query] into the search field and waits for the debounce.
Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Opens the search bar from the toolbar.
Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search'));
  await tester.pump();
}

/// The text of the search counter, or an empty string.
String counterText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(bodySearchCounterKey)).data ?? '';
