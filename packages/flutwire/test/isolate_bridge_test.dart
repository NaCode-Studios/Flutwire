import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/engine.dart';
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

const _wired = FlutwireConfig(
  enabled: true,
  persist: false,
  shortcut: false,
  notification: FlutwireNotificationConfig(enabled: false),
  redaction: FlutwireRedaction(queryParameters: {'token'}),
);

final _uri = Uri.parse('https://api.test/');

FlutwireEngine _engine([FlutwireConfig config = _quiet]) {
  final engine = FlutwireEngine(
    config: config,
    store: MemoryFlutwireStore(notifyInterval: Duration.zero),
  );
  addTearDown(engine.dispose);
  return engine;
}

/// Gives what another isolate sent time to arrive.
Future<void> _arrives() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

/// The history once [count] calls have finished in it, or as it is after five
/// seconds.
Future<List<FlutwireCall>> _history(
  FlutwireRuntime runtime, {
  int count = 1,
}) async {
  for (var i = 0; i < 100; i++) {
    final calls = runtime.store.calls.value;
    if (calls.length >= count && calls.every((call) => !call.isPending)) {
      return calls;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return runtime.store.calls.value;
}

/// A call over the network, made from whichever isolate runs it.
Future<int> _fetch(int port) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/todos?token=s3cret'),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<int> _fetchTwice(int port) async {
  await _fetch(port);
  return _fetch(port);
}

Future<int> _fetchFrom(int port) => _fetch(port);

// A closure carries everything in the scope it was written in. Written inside
// a test it would take the runtime along, which cannot be sent to another
// isolate, so the computations for an isolate are made here, where the port is
// all there is.
Future<int> Function() _twice(int port) =>
    () => _fetchTwice(port);

Future<int> Function() _afterLeaving(int port) => () async {
  await Flutwire.attach();
  await Flutwire.detach();
  return _fetch(port);
};

Future<Never> _fail() async => throw StateError('no network here');

Future<HttpServer> _serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response
      ..headers.contentType = ContentType.json
      ..write('{"ok":true}');
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return server;
}

void main() {
  setUp(() {
    mockNative();
    FlutwireIsolateBridge.forgetTold();
  });

  tearDown(() async {
    await Flutwire.detach();
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

    test('keeps a name that tells something', () {
      expect(FlutwireIsolateBridge.describe('parser'), 'parser');
    });

    test('cuts a name that runs to a whole line', () {
      final name = FlutwireIsolateBridge.describe(
        'Closure: (int) => Future<int> from Function main.<anonymous closure>',
      );
      expect(name.length, lessThanOrEqualTo(48));
      expect(name, endsWith('…'));
    });

    test('has a word for an isolate with no name', () {
      expect(FlutwireIsolateBridge.describe(null), 'an isolate');
      expect(FlutwireIsolateBridge.describe('  '), 'an isolate');
    });
  });

  group('an adapter in an isolate that has no recorder', () {
    test('tells the main isolate, once', () async {
      final engine = _engine();
      final bridge = FlutwireIsolateBridge.listen(engine)!;
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
      await _arrives();

      final note = engine.coverage.notes.value.single;
      expect(note.subject, startsWith('Dio in '));
      expect(note.count, 1);
    });

    test('tells about each adapter separately', () async {
      final engine = _engine();
      final bridge = FlutwireIsolateBridge.listen(engine)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;

      Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.dio);
      Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.http);
      await _arrives();

      final subjects = engine.coverage.notes.value.map((n) => n.subject);
      expect(subjects.map((s) => s.split(' in ').first), ['Dio', 'http']);
    });

    test(
      'says nothing in the main isolate, where a release build lands',
      () async {
        final engine = _engine();
        final bridge = FlutwireIsolateBridge.listen(engine)!;
        addTearDown(bridge.close);

        Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.dio);
        await _arrives();

        expect(engine.coverage.notes.value, isEmpty);
      },
    );

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

  group('an isolate that attaches', () {
    test('records into the history of the main isolate', () async {
      final main = _engine();
      final bridge = FlutwireIsolateBridge.listen(main)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;

      await Flutwire.attach();
      final recorder = Flutwire.begin(
        method: 'GET',
        uri: _uri,
        source: FlutwireSource.custom,
      )!;
      recorder
        ..responseHead(
          statusCode: 200,
          headers: FlutwireHeaders([
            const MapEntry('content-type', 'text/plain'),
          ]),
        )
        ..responseBody(utf8.encode('hello'))
        ..complete();
      await _arrives();

      final call = main.store.calls.value.single;
      expect(call.uri, _uri);
      expect(call.statusCode, 200);
      expect(utf8.decode(call.response!.body.bytes), 'hello');
      expect(call.state, FlutwireCallState.completed);
    });

    test(
      'records with the redaction and the limit of the main isolate',
      () async {
        final main = _engine(
          const FlutwireConfig(
            enabled: true,
            captureDartIo: false,
            persist: false,
            maxBodyBytes: 4,
            redaction: FlutwireRedaction(headers: {'x-secret'}),
          ),
        );
        final bridge = FlutwireIsolateBridge.listen(main)!;
        addTearDown(bridge.close);
        Flutwire.isRootIsolate = () => false;

        await Flutwire.attach();
        final recorder = Flutwire.begin(
          method: 'POST',
          uri: _uri,
          source: FlutwireSource.custom,
          requestHeaders: FlutwireHeaders([
            const MapEntry('x-secret', 'hunter2'),
          ]),
        )!;
        recorder
          ..requestBody(utf8.encode('0123456789'))
          ..requestSent()
          ..complete();
        await _arrives();

        final call = main.store.calls.value.single;
        expect(call.request.headers.first('x-secret'), '[redacted]');
        expect(call.request.body.bytes, hasLength(4));
        expect(call.request.body.totalBytes, 10);
      },
    );

    test('is not recorded while the main isolate is paused', () async {
      final main = _engine();
      final bridge = FlutwireIsolateBridge.listen(main)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;
      await Flutwire.attach();

      main.paused.value = true;
      Flutwire.begin(
        method: 'GET',
        uri: _uri,
        source: FlutwireSource.custom,
      )!.complete();
      await _arrives();

      expect(main.store.calls.value, isEmpty);
    });

    test(
      'is left out when an ignore rule of the main isolate says so',
      () async {
        final main = _engine(
          FlutwireConfig(
            enabled: true,
            captureDartIo: false,
            persist: false,
            ignore: [FlutwireIgnore.host('api.test')],
          ),
        );
        final bridge = FlutwireIsolateBridge.listen(main)!;
        addTearDown(bridge.close);
        Flutwire.isRootIsolate = () => false;
        await Flutwire.attach();

        Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.custom)!
          ..requestSent()
          ..complete();
        Flutwire.begin(
          method: 'GET',
          uri: Uri.parse('https://other.test/'),
          source: FlutwireSource.custom,
        )!.complete();
        await _arrives();

        expect(main.store.calls.value.single.host, 'other.test');
      },
    );

    test(
      'does nothing in the main isolate, which records for itself',
      () async {
        final main = _engine();
        final bridge = FlutwireIsolateBridge.listen(main)!;
        addTearDown(bridge.close);
        Flutwire.isRootIsolate = () => true;

        await Flutwire.attach();

        expect(FlutwireIsolateLink.engine, isNull);
      },
    );

    test('does nothing when the main isolate is not recording', () async {
      Flutwire.isRootIsolate = () => false;

      await Flutwire.attach();

      expect(FlutwireIsolateLink.engine, isNull);
      expect(
        Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.custom),
        isNull,
      );
    });

    test('stops recording once it detaches', () async {
      final main = _engine();
      final bridge = FlutwireIsolateBridge.listen(main)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;
      await Flutwire.attach();
      expect(FlutwireIsolateLink.engine, isNotNull);

      await Flutwire.detach();

      expect(FlutwireIsolateLink.engine, isNull);
      expect(
        Flutwire.begin(method: 'GET', uri: _uri, source: FlutwireSource.custom),
        isNull,
      );
    });

    test('attaching twice is the same as once', () async {
      final main = _engine();
      final bridge = FlutwireIsolateBridge.listen(main)!;
      addTearDown(bridge.close);
      Flutwire.isRootIsolate = () => false;

      await Future.wait([Flutwire.attach(), Flutwire.attach()]);
      final engine = FlutwireIsolateLink.engine;
      await Flutwire.attach();

      expect(engine, isNotNull);
      expect(FlutwireIsolateLink.engine, same(engine));
    });
  });

  group('Flutwire.run and Flutwire.compute', () {
    test('give back what the computation gives back', () async {
      expect(await Flutwire.run(() => 6 * 7), 42);
      expect(await Flutwire.compute((int n) => n + 1, 41), 42);
    });

    test('pass on the error of the computation', () async {
      await expectLater(Flutwire.run(_fail), throwsA(isA<StateError>()));
    });

    testWidgets('record the calls the isolate makes', (tester) async {
      await tester.runAsync(() async {
        final server = await _serve();
        final runtime = (await FlutwireRuntime.start(
          _wired,
          navigatorKey: GlobalKey<NavigatorState>(),
        ))!;
        addTearDown(() => tester.runAsync(runtime.dispose));
        final port = server.port;

        expect(await Flutwire.run(_twice(port)), 200);

        final calls = await _history(runtime, count: 2);
        expect(calls, hasLength(2));
        expect(calls.map((c) => c.id).toSet(), hasLength(2));
        for (final call in calls) {
          expect(call.source, FlutwireSource.io);
          expect(call.statusCode, 200);
          expect(call.state, FlutwireCallState.completed);
          expect(utf8.decode(call.response!.body.bytes), '{"ok":true}');
          expect(call.uri.queryParameters['token'], '[redacted]');
        }
      });
    });

    testWidgets('and so does compute', (tester) async {
      await tester.runAsync(() async {
        final server = await _serve();
        final runtime = (await FlutwireRuntime.start(
          _wired,
          navigatorKey: GlobalKey<NavigatorState>(),
        ))!;
        addTearDown(() => tester.runAsync(runtime.dispose));

        expect(await Flutwire.compute(_fetchFrom, server.port), 200);

        final calls = await _history(runtime);
        expect(calls.single.statusCode, 200);
        expect(calls.single.uri.host, '127.0.0.1');
      });
    });

    testWidgets('leave no capture behind in the isolate that ran them', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final server = await _serve();
        final runtime = (await FlutwireRuntime.start(
          _wired,
          navigatorKey: GlobalKey<NavigatorState>(),
        ))!;
        addTearDown(() => tester.runAsync(runtime.dispose));
        final port = server.port;

        // The isolate attaches, detaches, and then makes a call of its own.
        final answer = await Flutwire.run(_afterLeaving(port));
        await _arrives();

        expect(answer, 200);
        expect(runtime.store.calls.value, isEmpty);
      });
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
