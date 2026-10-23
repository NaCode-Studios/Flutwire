import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

import 'support/native_channel.dart';

const _config = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  notification: FlutwireNotificationConfig(enabled: false),
);

void main() {
  setUp(mockNative);
  tearDown(Flutwire.reset);

  group('before init', () {
    test('records nothing and every member is harmless', () async {
      expect(Flutwire.isActive, isFalse);
      expect(Flutwire.config.enabled, isNull);
      expect(Flutwire.calls.value, isEmpty);
      expect(Flutwire.store, isNull);
      expect(Flutwire.isPaused, isFalse);
      expect(Flutwire.wireCaptureActive, isFalse);
      expect(
        Flutwire.begin(
          method: 'GET',
          uri: Uri.parse('https://api.test/'),
          source: FlutwireSource.custom,
        ),
        isNull,
      );

      Flutwire.isPaused = true;
      await Flutwire.clear();
      await Flutwire.open();

      expect(Flutwire.isPaused, isFalse);
    });
  });

  group('init', () {
    testWidgets('starts recording', (tester) async {
      await tester.runAsync(() => Flutwire.init(config: _config));

      expect(Flutwire.isActive, isTrue);
      expect(Flutwire.store, isNotNull);
      expect(Flutwire.config.captureDartIo, isFalse);
    });

    testWidgets('stays off when the configuration says so', (tester) async {
      await tester.runAsync(
        () => Flutwire.init(config: const FlutwireConfig(enabled: false)),
      );

      expect(Flutwire.isActive, isFalse);
    });

    testWidgets('does nothing when called again', (tester) async {
      await tester.runAsync(() async {
        await Flutwire.init(config: _config);
        await Flutwire.init(config: const FlutwireConfig(enabled: false));
      });

      expect(Flutwire.isActive, isTrue);
    });

    testWidgets('never throws, even when the native half answers nonsense', (
      tester,
    ) async {
      mockNative((call) async => {'storagePath': 5});

      await tester.runAsync(() => Flutwire.init(config: _config));

      expect(Flutwire.isActive, isFalse);
    });
  });

  group('once started', () {
    testWidgets('begin hands out a recorder whose call lands in the history', (
      tester,
    ) async {
      await tester.runAsync(() => Flutwire.init(config: _config));

      Flutwire.begin(
          method: 'post',
          uri: Uri.parse('https://api.test/items'),
          source: FlutwireSource.custom,
        )!
        ..requestSent()
        ..responseHead(statusCode: 201, headers: FlutwireHeaders.empty)
        ..complete();
      (Flutwire.store! as MemoryFlutwireStore).flush();

      expect(Flutwire.calls.value, hasLength(1));
      expect(Flutwire.calls.value.single.method, 'POST');
      expect(Flutwire.calls.value.single.statusCode, 201);
    });

    testWidgets('pausing stops the recording and resuming restarts it', (
      tester,
    ) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      FlutwireCallRecorder? start() => Flutwire.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test/'),
        source: FlutwireSource.custom,
      );

      Flutwire.isPaused = true;
      expect(Flutwire.isPaused, isTrue);
      expect(start(), isNull);

      Flutwire.isPaused = false;
      expect(start(), isNotNull);
      // Publishing starts the store's notification timer; end it here.
      (Flutwire.store! as MemoryFlutwireStore).flush();
    });

    testWidgets('clear empties the history but keeps what is pinned', (
      tester,
    ) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      final store = Flutwire.store! as MemoryFlutwireStore;
      for (final path in ['a', 'b']) {
        Flutwire.begin(
            method: 'GET',
            uri: Uri.parse('https://api.test/$path'),
            source: FlutwireSource.custom,
          )!
          ..requestSent()
          ..complete();
      }
      store.flush();
      await store.setPinned([store.calls.value.last.id], pinned: true);

      await tester.runAsync(Flutwire.clear);
      store.flush();
      expect(Flutwire.calls.value, hasLength(1));

      await tester.runAsync(() => Flutwire.clear(keepPinned: false));
      store.flush();
      expect(Flutwire.calls.value, isEmpty);
    });

    testWidgets('open puts the inspector above the app', (tester) async {
      await tester.runAsync(() => Flutwire.init(config: _config));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: Flutwire.navigatorKey,
          home: const Scaffold(body: Text('the app')),
        ),
      );

      unawaited(Flutwire.open());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Network activity'), findsOneWidget);
    });
  });
}
