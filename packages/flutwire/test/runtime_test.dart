import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/platform/native.dart';
import 'package:flutwire/src/runtime.dart';

import 'support/native_channel.dart';

const _memory = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
);

const _quiet = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  notification: FlutwireNotificationConfig(enabled: false),
);

/// Starts a runtime the way the facade does, and stops it when the test ends.
Future<FlutwireRuntime> start(
  WidgetTester tester,
  FlutwireConfig config, {
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  final runtime = await tester.runAsync(
    () => FlutwireRuntime.start(
      config,
      navigatorKey: navigatorKey ?? GlobalKey<NavigatorState>(),
    ),
  );
  addTearDown(() async {
    await tester.runAsync(() => runtime!.dispose());
  });
  return runtime!;
}

void main() {
  setUp(mockNative);

  group('starting', () {
    testWidgets('gives nothing back when the configuration says off', (
      tester,
    ) async {
      final runtime = await tester.runAsync(
        () => FlutwireRuntime.start(
          const FlutwireConfig(enabled: false),
          navigatorKey: GlobalKey<NavigatorState>(),
        ),
      );

      expect(runtime, isNull);
    });

    testWidgets('keeps the history in memory when told not to persist', (
      tester,
    ) async {
      final runtime = await start(tester, _quiet);

      expect(runtime.store, isA<MemoryFlutwireStore>());
      expect(runtime.config, same(_quiet));
    });

    testWidgets('records into the store through the engine', (tester) async {
      final runtime = await start(tester, _quiet);

      runtime.engine.begin(
          method: 'GET',
          uri: Uri.parse('https://api.test/'),
          source: FlutwireSource.custom,
        )!
        ..requestSent()
        ..complete();
      (runtime.store as MemoryFlutwireStore).flush();

      expect(runtime.store.calls.value, hasLength(1));
    });
  });

  group('the notification', () {
    testWidgets('is unsupported when there is no native half', (tester) async {
      final runtime = await start(tester, _memory);

      expect(
        runtime.notificationPermission.value,
        FlutwireNotificationPermission.unsupported,
      );
    });

    testWidgets('takes the permission the native half reports', (tester) async {
      mockNative((call) async {
        if (call.method == 'initialize') {
          return {
            'permission': 'denied',
            'storagePath': null,
            'temporaryPath': null,
          };
        }
        return null;
      });

      final runtime = await start(tester, _memory);

      expect(
        runtime.notificationPermission.value,
        FlutwireNotificationPermission.denied,
      );
    });
  });

  group('recording', () {
    testWidgets('pauses and resumes', (tester) async {
      final runtime = await start(tester, _quiet);
      FlutwireCallRecorder? begin() => runtime.engine.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test/'),
        source: FlutwireSource.custom,
      );

      runtime.paused.value = true;
      expect(runtime.paused.value, isTrue);
      expect(begin(), isNull);

      runtime.paused.value = false;
      expect(runtime.paused.value, isFalse);
      expect(begin(), isNotNull);
      (runtime.store as MemoryFlutwireStore).flush();
    });

    testWidgets('clears the history except what is pinned', (tester) async {
      final runtime = await start(tester, _quiet);
      final store = runtime.store as MemoryFlutwireStore;
      for (final path in ['a', 'b']) {
        runtime.engine.begin(
            method: 'GET',
            uri: Uri.parse('https://api.test/$path'),
            source: FlutwireSource.custom,
          )!
          ..requestSent()
          ..complete();
      }
      store.flush();
      await tester.runAsync(
        () => store.setPinned([store.calls.value.first.id], pinned: true),
      );

      await tester.runAsync(runtime.clear);
      store.flush();

      expect(store.calls.value, hasLength(1));
    });
  });

  group('what the native half sends', () {
    testWidgets('clear in the notification empties the history', (
      tester,
    ) async {
      final runtime = await start(tester, _quiet);
      final store = runtime.store as MemoryFlutwireStore;
      runtime.engine.begin(
          method: 'GET',
          uri: Uri.parse('https://api.test/'),
          source: FlutwireSource.custom,
        )!
        ..requestSent()
        ..complete();
      store.flush();
      expect(store.calls.value, hasLength(1));

      await tester.runAsync(() => sendNativeAction('clear'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      store.flush();

      expect(store.calls.value, isEmpty);
    });

    testWidgets('open in the notification shows the inspector', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await start(tester, _quiet, navigatorKey: key);
      await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const Text('the app')),
      );

      await tester.runAsync(() => sendNativeAction('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Network activity'), findsOneWidget);
    });

    testWidgets('an action that launched the app is taken at start', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      mockNative(
        (call) async => call.method == 'consumeAction' ? 'open' : null,
      );
      await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const Text('the app')),
      );

      await start(tester, _quiet, navigatorKey: key);
      // The runtime looks for the navigator on a real timer.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Network activity'), findsOneWidget);
    });
  });

  group('the look of the inspector', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flutwire_theme_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    FlutwireConfig onDisk([ThemeMode mode = ThemeMode.system]) =>
        FlutwireConfig(
          enabled: true,
          captureDartIo: false,
          shortcut: false,
          notification: const FlutwireNotificationConfig(enabled: false),
          storagePath: root.path,
          themeMode: mode,
        );

    Future<void> restart(WidgetTester tester, FlutwireRuntime runtime) =>
        tester.runAsync(runtime.dispose).then((_) {});

    testWidgets('starts as the app configured it', (tester) async {
      final runtime = await start(tester, onDisk(ThemeMode.dark));

      expect(runtime.themeMode.value, ThemeMode.dark);
    });

    testWidgets('is remembered across a restart and wins over the config', (
      tester,
    ) async {
      final first = await start(tester, onDisk(ThemeMode.dark));
      await tester.runAsync(
        () async => first.themeMode.value = ThemeMode.light,
      );
      await restart(tester, first);

      final second = await start(tester, onDisk(ThemeMode.dark));

      expect(second.themeMode.value, ThemeMode.light);
    });

    testWidgets('survives clearing the history', (tester) async {
      final first = await start(tester, onDisk());
      await tester.runAsync(() async {
        first.themeMode.value = ThemeMode.dark;
        await first.clear(keepPinned: false);
      });
      await restart(tester, first);

      final second = await start(tester, onDisk());

      expect(second.themeMode.value, ThemeMode.dark);
    });

    testWidgets('ignores a stored value it does not know', (tester) async {
      await tester.runAsync(
        () => File(
          '${root.path}/preferences.json',
        ).writeAsString('{"themeMode":"sepia"}'),
      );

      final runtime = await start(tester, onDisk(ThemeMode.light));

      expect(runtime.themeMode.value, ThemeMode.light);
    });
  });
}
