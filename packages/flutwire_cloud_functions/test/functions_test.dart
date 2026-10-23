import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_cloud_functions/flutwire_cloud_functions.dart';

import 'fakes.dart';

List<FlutwireCall> recorded() {
  (Flutwire.store! as MemoryFlutwireStore).flush();
  return Flutwire.calls.value.reversed.toList();
}

/// Installs the recording over a fake plugin and returns the callable the app
/// would get for [name].
HttpsCallablePlatform callable(
  String name, {
  required Handler handler,
  Events? events,
  String region = 'us-central1',
  String? origin,
}) {
  FirebaseFunctionsPlatform.instance = FakeFunctions(handler, events: events);
  FlutwireCloudFunctions.install(projectId: 'demo-app');
  return FirebaseFunctionsPlatform.instanceFor(
    region: region,
  ).httpsCallable(origin, name, HttpsCallableOptions());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Flutwire.init(
      config: const FlutwireConfig(
        enabled: true,
        persist: false,
        captureDartIo: false,
        shortcut: false,
        notification: FlutwireNotificationConfig(enabled: false),
      ),
    );
  });

  tearDown(() async {
    FlutwireCloudFunctions.uninstall();
    await Flutwire.reset();
  });

  test(
    'records the name, the payload and the result, and passes both on',
    () async {
      final reply = {'ok': true};
      final fn = callable(
        'createClub',
        handler: (parameters) => reply,
        region: 'europe-west1',
      );

      final result = await fn.call({'name': 'Orion'});

      expect(identical(result, reply), isTrue);
      final call = recorded().single;
      expect(call.source, FlutwireSource.functions);
      expect(call.method, 'CALL');
      expect(
        call.uri.toString(),
        'https://europe-west1-demo-app.cloudfunctions.net/createClub',
      );
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 200);
      expect(call.request.body.jsonValue, {
        'data': {'name': 'Orion'},
      });
      expect(call.response!.body.jsonValue, {
        'result': {'ok': true},
      });
    },
  );

  test('a function called by URL keeps the URL it was given', () async {
    FirebaseFunctionsPlatform.instance = FakeFunctions((p) => 1);
    FlutwireCloudFunctions.install(projectId: 'demo-app');
    final fn = FirebaseFunctionsPlatform.instanceFor(region: 'us-central1')
        .httpsCallableWithUri(
          null,
          Uri.parse('https://create-club-abc123-ew.a.run.app'),
          HttpsCallableOptions(),
        );

    await fn.call();

    final call = recorded().single;
    expect(call.uri.host, 'create-club-abc123-ew.a.run.app');
    expect(call.request.body.jsonValue, {'data': null});
  });

  test('a function on the emulator is shown at the emulator address', () async {
    final fn = callable(
      'ping',
      handler: (p) => 'pong',
      origin: 'http://localhost:5001',
    );

    await fn.call();

    expect(
      recorded().single.uri.toString(),
      'http://localhost:5001/demo-app/us-central1/ping',
    );
  });

  group('an error from the function', () {
    test('shows the status Firebase answers with, and still throws', () async {
      final fn = callable(
        'secret',
        handler: (p) => throw FakeException(
          'permission-denied',
          'Not your club',
          details: {'club': 'c1'},
        ),
      );

      await expectLater(
        fn.call({'id': 1}),
        throwsA(
          isA<FirebaseFunctionsException>()
              .having((e) => e.code, 'code', 'permission-denied')
              .having((e) => e.message, 'message', 'Not your club'),
        ),
      );

      final call = recorded().single;
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 403);
      expect(call.response!.reasonPhrase, 'permission-denied');
      expect(call.response!.body.jsonValue, {
        'error': {
          'message': 'Not your club',
          'status': 'PERMISSION_DENIED',
          'details': {'club': 'c1'},
        },
      });
    });

    test('maps the codes a server can answer with', () async {
      const expected = {
        'invalid-argument': 400,
        'unauthenticated': 401,
        'not-found': 404,
        'already-exists': 409,
        'resource-exhausted': 429,
        'internal': 500,
        'unimplemented': 501,
      };
      for (final entry in expected.entries) {
        final fn = callable(
          'f',
          handler: (p) => throw FakeException(entry.key, 'x'),
        );
        await expectLater(
          fn.call(),
          throwsA(isA<FirebaseFunctionsException>()),
        );
        FlutwireCloudFunctions.uninstall();
      }
      expect(recorded().map((c) => c.statusCode), expected.values);
    });

    test('a call that got no answer is a failed call', () async {
      final fn = callable(
        'slow',
        handler: (p) => throw FakeException('unavailable', 'No network'),
      );

      await expectLater(fn.call(), throwsA(isA<FirebaseFunctionsException>()));

      final call = recorded().single;
      expect(call.state, FlutwireCallState.failed);
      expect(call.response, isNull);
    });

    test('any other error reaches the app untouched', () async {
      final boom = StateError('boom');
      final fn = callable('f', handler: (p) => throw boom);

      await expectLater(fn.call(), throwsA(same(boom)));

      expect(recorded().single.state, FlutwireCallState.failed);
    });
  });

  group('a stream', () {
    test('records each event as a line and completes', () async {
      final fn = callable(
        'progress',
        handler: (p) => null,
        events: (p) => Stream.fromIterable([
          {'step': 1},
          {'step': 2},
        ]),
      );

      final seen = await fn.stream({'job': 'a'}).toList();

      expect(seen, [
        {'step': 1},
        {'step': 2},
      ]);
      final call = recorded().single;
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 200);
      expect(call.response!.body.text, '{"step":1}\n{"step":2}\n');
    });

    test('a listener that leaves early makes a cancelled call', () async {
      final fn = callable(
        'forever',
        handler: (p) => null,
        events: (p) => Stream.periodic(
          const Duration(milliseconds: 5),
          (i) => {'tick': i},
        ),
      );

      final subscription = fn.stream(null).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await subscription.cancel();

      expect(recorded().single.state, FlutwireCallState.cancelled);
    });

    test('an error in the stream is recorded and rethrown', () async {
      final fn = callable(
        'broken',
        handler: (p) => null,
        events: (p) async* {
          yield {'step': 1};
          throw FakeException('internal', 'went wrong');
        },
      );

      await expectLater(
        fn.stream(null).toList(),
        throwsA(isA<FirebaseFunctionsException>()),
      );

      final call = recorded().single;
      expect(call.statusCode, 200);
      expect(call.state, FlutwireCallState.completed);
    });
  });

  group('never getting in the way', () {
    test('a paused recording lets the call through unrecorded', () async {
      final fn = callable('quiet', handler: (p) => 'fine');
      Flutwire.isPaused = true;

      expect(await fn.call(), 'fine');

      expect(recorded(), isEmpty);
    });

    test('a payload that is not JSON does not stop the call', () async {
      final fn = callable('odd', handler: (p) => 'fine');

      expect(await fn.call(Object()), 'fine');

      expect(recorded().single.state, FlutwireCallState.completed);
    });

    test('the options the app changes later reach the real callable', () async {
      HttpsCallableOptions? seen;
      FirebaseFunctionsPlatform.instance = FakeFunctions((p) => 1);
      FlutwireCloudFunctions.install(projectId: 'demo-app');
      final fn = FirebaseFunctionsPlatform.instanceFor(
        region: 'us-central1',
      ).httpsCallable(null, 'f', HttpsCallableOptions());
      expect(fn, isA<HttpsCallablePlatform>());
      fn.options = HttpsCallableOptions(timeout: const Duration(seconds: 5));
      await fn.call();
      seen = fn.options;

      expect(seen.timeout, const Duration(seconds: 5));
    });

    test('installing twice wraps the plugin once', () async {
      FirebaseFunctionsPlatform.instance = FakeFunctions((p) => 1);
      FlutwireCloudFunctions.install();
      final first = FirebaseFunctionsPlatform.instance;
      FlutwireCloudFunctions.install();

      expect(FirebaseFunctionsPlatform.instance, same(first));
      expect(FlutwireCloudFunctions.isInstalled, isTrue);
    });

    test('does nothing while Flutwire is not recording', () async {
      await Flutwire.reset();
      final fake = FakeFunctions((p) => 1);
      FirebaseFunctionsPlatform.instance = fake;

      FlutwireCloudFunctions.install();

      expect(FlutwireCloudFunctions.isInstalled, isFalse);
      expect(FirebaseFunctionsPlatform.instance, same(fake));
    });
  });
}
