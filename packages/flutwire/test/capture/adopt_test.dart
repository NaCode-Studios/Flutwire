import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/engine.dart';

const _config = FlutwireConfig(
  enabled: true,
  captureDartIo: false,
  persist: false,
  notification: FlutwireNotificationConfig(enabled: false),
);

final _start = DateTime.utc(2026, 10, 24, 12);

FlutwireCall _call(
  int id, {
  String url = 'https://api.test/a',
  DateTime? at,
  FlutwireCallState state = FlutwireCallState.pending,
}) => FlutwireCall(
  id: id,
  method: 'GET',
  uri: Uri.parse(url),
  source: FlutwireSource.io,
  state: state,
  startedAt: at ?? _start,
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
);

FlutwireEngine _engine([FlutwireConfig config = _config]) {
  final engine = FlutwireEngine(
    config: config,
    store: MemoryFlutwireStore(notifyInterval: Duration.zero),
  );
  addTearDown(engine.dispose);
  return engine;
}

Future<List<FlutwireCall>> _calls(FlutwireEngine engine) async {
  await Future<void>.delayed(Duration.zero);
  return engine.store.calls.value;
}

void main() {
  group('a call recorded in another isolate', () {
    test('takes the time it started as its id', () async {
      final engine = _engine();

      engine.adopt(_call(1), origin: 1, finished: false);

      final call = (await _calls(engine)).single;
      expect(call.id, _start.microsecondsSinceEpoch);
      expect(call.uri, Uri.parse('https://api.test/a'));
    });

    test('is the same call at every snapshot', () async {
      final engine = _engine();

      engine.adopt(_call(1), origin: 1, finished: false);
      engine.adopt(
        _call(1, state: FlutwireCallState.completed),
        origin: 1,
        finished: true,
      );

      final calls = await _calls(engine);
      expect(calls, hasLength(1));
      expect(calls.single.state, FlutwireCallState.completed);
    });

    test(
      'is a different call from the one another isolate numbered the same',
      () async {
        final engine = _engine();

        engine.adopt(
          _call(7, url: 'https://api.test/first'),
          origin: 1,
          finished: false,
        );
        engine.adopt(
          _call(7, url: 'https://api.test/second'),
          origin: 2,
          finished: false,
        );

        final calls = await _calls(engine);
        expect(calls.map((c) => c.uri.path), ['/second', '/first']);
        expect(calls.map((c) => c.id).toSet(), hasLength(2));
      },
    );

    test('never takes an id the engine has given out', () async {
      final engine = _engine();
      final own = engine.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test/own'),
        source: FlutwireSource.custom,
      )!;

      // Started a minute ago, but the engine has numbered calls since.
      engine.adopt(
        _call(1, at: DateTime.fromMicrosecondsSinceEpoch(own.id - 60000000)),
        origin: 1,
        finished: false,
      );

      final calls = await _calls(engine);
      expect(calls, hasLength(2));
      expect(calls.first.id, greaterThan(own.id));
    });

    test(
      'is numbered anew when its number comes back after it finished',
      () async {
        final engine = _engine();

        engine.adopt(_call(1), origin: 1, finished: true);
        engine.adopt(_call(1), origin: 1, finished: true);

        expect(await _calls(engine), hasLength(2));
      },
    );

    test('is not recorded while recording is paused', () async {
      final engine = _engine();
      engine.paused.value = true;

      engine.adopt(_call(1), origin: 1, finished: true);

      expect(await _calls(engine), isEmpty);
    });

    test('is not recorded when an ignore rule matches', () async {
      final engine = _engine(
        FlutwireConfig(
          enabled: true,
          captureDartIo: false,
          persist: false,
          ignore: [FlutwireIgnore.pathPrefix('/noise')],
        ),
      );

      engine.adopt(
        _call(1, url: 'https://api.test/noise/a'),
        origin: 1,
        finished: true,
      );
      engine.adopt(
        _call(2, url: 'https://api.test/signal'),
        origin: 1,
        finished: true,
      );

      expect((await _calls(engine)).single.uri.path, '/signal');
    });

    test('is judged once, on its first snapshot', () async {
      final engine = _engine();
      engine.paused.value = true;
      engine.adopt(_call(1), origin: 1, finished: false);

      engine.paused.value = false;
      engine.adopt(_call(1), origin: 1, finished: false);
      engine.adopt(_call(1), origin: 1, finished: true);

      expect(await _calls(engine), isEmpty);
    });
  });

  group('an engine that forwards', () {
    test('hands every snapshot on and keeps nothing', () async {
      final seen = <(int, bool)>[];
      final engine = FlutwireEngine.forwarding(
        config: _config,
        forward: (call, {required finished}) => seen.add((call.id, finished)),
      );
      addTearDown(engine.dispose);

      engine
          .begin(
            method: 'GET',
            uri: Uri.parse('https://api.test/a'),
            source: FlutwireSource.custom,
          )!
          .complete();

      expect(seen.last.$2, isTrue);
      expect(seen.take(seen.length - 1).every((s) => !s.$2), isTrue);
      expect(seen.map((s) => s.$1).toSet(), hasLength(1));
      expect(engine.store.calls.value, isEmpty);
    });
  });
}
