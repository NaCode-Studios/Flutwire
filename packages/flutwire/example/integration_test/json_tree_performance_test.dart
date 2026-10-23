// Measures what a person does with a big JSON response in the inspector:
// opens it, scrolls it, collapses and expands it, and searches inside it. It
// goes through the public API and the real screens, so it needs a device, and
// it should run in profile mode, where frame times mean something:
//
//   flutter drive --profile --no-dds -d <device> \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/json_tree_performance_test.dart
//
// The timings land in build/integration_response_data.json, one entry per
// action and per document. `--no-dds` is needed in profile mode, where the test
// otherwise never starts. An emulator's rasterizer is slow for every screen, so
// read the build times there and the raster times only on a real device.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:integration_test/integration_test.dart';

/// A catalogue of objects with nested values, which is the usual shape of an
/// answer: about 6,000 nodes in 200 KB.
String catalogue() {
  final items = [
    for (var i = 0; i < 480; i++)
      {
        'id': i,
        'name': 'Item $i',
        'price': i * 1.25,
        'inStock': i.isEven,
        'tags': ['tag-${i % 7}', 'tag-${i % 11}', 'tag-${i % 13}'],
        'dimensions': {'width': 10 + i % 5, 'height': 20 + i % 7, 'depth': 3},
        'description':
            'A description of item $i, long enough to read like a sentence '
            'that somebody wrote about what the item is and who buys it.',
        'history': [
          for (var k = 0; k < 3; k++)
            {'at': '2026-10-24T10:0$k:00Z', 'by': 'user-${i % 9}'},
        ],
      },
  ];
  return jsonEncode({'items': items, 'total': items.length});
}

/// A flat array of numbers: the worst case for a tree, about 42,000 nodes in
/// 200 KB, each a row of its own.
String wideArray() =>
    jsonEncode([for (var i = 0; i < 42000; i++) (i * 7) % 10007]);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // On a phone every row of the tree has a menu of its own with the same
  // tooltip, and the one of the toolbar is the first.
  final moreActions = find.byTooltip('More actions').first;

  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> record(String path, String json) async {
    final bytes = utf8.encode(json);
    expect(bytes.length, greaterThanOrEqualTo(200000), reason: path);
    Flutwire.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test$path'),
        source: FlutwireSource.custom,
      )!
      ..requestSent()
      ..responseHead(
        statusCode: 200,
        headers: FlutwireHeaders.fromMap({'content-type': 'application/json'}),
      )
      ..responseBody(bytes)
      ..complete();
  }

  testWidgets('a 200 KB JSON response opens, scrolls, collapses and searches', (
    tester,
  ) async {
    await Flutwire.init(
      config: const FlutwireConfig(
        enabled: true,
        persist: false,
        captureDartIo: false,
        shortcut: false,
        maxBodyBytes: 400000,
        notification: FlutwireNotificationConfig(enabled: false),
        floatingButton: FlutwireButtonMode.never,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: Flutwire.navigatorKey,
        home: const Scaffold(body: Center(child: Text('the app'))),
      ),
    );
    await record('/catalogue', catalogue());
    await record('/numbers', wideArray());
    unawaited(Flutwire.open());
    await settle(tester);

    for (final (path, key) in [
      ('/catalogue', 'objects'),
      ('/numbers', 'wide_array'),
    ]) {
      await tester.tap(find.text(path));
      await settle(tester);

      // Each thing a person does is measured on its own, so a slow frame can be
      // blamed on the action that caused it.
      await binding.watchPerformance(() async {
        await tester.tap(find.text('Response'));
        await settle(tester, 20);
      }, reportKey: '${key}_open');

      await binding.watchPerformance(() async {
        final tree = find.byType(Scrollable).last;
        for (var i = 0; i < 4; i++) {
          await tester.fling(tree, const Offset(0, -700), 2500);
          await settle(tester, 8);
        }
        for (var i = 0; i < 4; i++) {
          await tester.fling(tree, const Offset(0, 700), 2500);
          await settle(tester, 8);
        }
      }, reportKey: '${key}_scroll');

      await binding.watchPerformance(() async {
        for (final action in ['Collapse all', 'Expand all', 'Collapse all']) {
          await tester.tap(moreActions);
          await settle(tester, 4);
          await tester.tap(find.text(action));
          await settle(tester, 10);
        }
        await tester.tap(moreActions);
        await settle(tester, 4);
        await tester.tap(find.text('Expand all'));
        await settle(tester, 10);
      }, reportKey: '${key}_collapse');

      await binding.watchPerformance(() async {
        await tester.tap(find.byTooltip('Search'));
        await settle(tester, 4);
        await tester.enterText(find.byType(TextField), '1');
        await settle(tester, 10);
        for (var i = 0; i < 12; i++) {
          await tester.tap(find.byTooltip('Next match'));
          await settle(tester, 3);
        }
      }, reportKey: '${key}_search');

      // Back to the list for the next document.
      await tester.pageBack();
      await settle(tester);
    }
  });
}
