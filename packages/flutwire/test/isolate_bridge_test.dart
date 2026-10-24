import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/isolate_bridge.dart';
import 'package:flutwire/src/runtime.dart';

import 'support/native_channel.dart';

const _quiet = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  shortcut: false,
  notification: FlutwireNotificationConfig(enabled: false),
);

final _uri = Uri.parse('https://api.test/');

void main() {
  setUp(() {
    mockNative();
    FlutwireIsolateBridge.forgetTold();
  });

  tearDown(() async {
    await Flutwire.reset();
    Flutwire.isRootIsolate = () => true;
  });

  group('naming an isolate', () {
    test('says Isolate.run for the name the VM gives it', () {
      expect(
        FlutwireIsolateBridge.describe('_RemoteRunner._remoteExecute'),
        'Isolate.run',
      );
    });

    test('keeps a name somebody chose', () {
      expect(FlutwireIsolateBridge.describe('parser'), 'parser');
    });

    test('cuts the line compute makes from its callback', () {
      final name = FlutwireIsolateBridge.describe(
        "Closure: (Map<String, dynamic>) => String from Function 'decode': "
        'static.',
      );

      expect(name, hasLength(48));
      expect(name, endsWith('…'));
    });

    test('has a word for an isolate with no name', () {
      expect(FlutwireIsolateBridge.describe(null), 'an isolate');
      expect(FlutwireIsolateBridge.describe('  '), 'an isolate');
    });
  });

  group('an adapter in an isolate that has no recorder', () {
    test('tells the main isolate, once', () async {
      final told = <String>[];
      final bridge = FlutwireIsolateBridge.listen(told.add)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;

      for (var i = 0; i < 3; i++) {
        final recorder = Flutwire.begin(
          method: 'GET',
          uri: _uri,
          source: FlutwireSource.dio,
        );
        expect(recorder, isNull);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(told, hasLength(1));
      expect(told.single, startsWith('Dio in '));
    });

    test('tells about each adapter separately', () async {
      final told = <String>[];
      final bridge = FlutwireIsolateBridge.listen(told.add)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;

      Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.dio);
      Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.http);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(told.map((s) => s.split(' in ').first), ['Dio', 'http']);
    });

    test('says nothing in the main isolate, where a release build lands', () {
      final told = <String>[];
      final bridge = FlutwireIsolateBridge.listen(told.add)!;
      addTearDown(bridge.close);

      Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.dio);

      expect(told, isEmpty);
    });

    test('does nothing when the main isolate is not listening', () {
      Flutwire.isRootIsolate = () => false;

      expect(
        () => Flutwire.begin(
          method: 'GET',
          uri: _uri,
          source: FlutwireSource.dio,
        ),
        returnsNormally,
      );
    });
  });

  testWidgets('what other isolates report becomes a note', (tester) async {
    final runtime = await tester.runAsync(
      () => FlutwireRuntime.start(
        _quiet,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );
    addTearDown(() async {
      await tester.runAsync(() => runtime!.dispose());
    });
    expect(runtime!.coverage.value, isEmpty);

    await tester.runAsync(() async {
      Flutwire.isRootIsolate = () => false;
      // Another isolate sends through the same named port.
      FlutwireIsolateBridge.tell(FlutwireSource.dio);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    final note = runtime.coverage.value.single;
    expect(note.gap, FlutwireGap.otherIsolate);
    expect(note.subject, startsWith('Dio in '));
  });

  testWidgets('and the bridge is closed with the runtime', (tester) async {
    final runtime = await tester.runAsync(
      () => FlutwireRuntime.start(
        _quiet,
        navigatorKey: GlobalKey<NavigatorState>(),
      ),
    );
    await tester.runAsync(() => runtime!.dispose());

    await tester.runAsync(() async {
      FlutwireIsolateBridge.tell(FlutwireSource.dio);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    expect(runtime!.coverage.value, isEmpty);
  });
}
