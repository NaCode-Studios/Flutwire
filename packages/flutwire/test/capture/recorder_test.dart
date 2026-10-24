import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/recorder.dart';
import 'package:flutwire/src/capture/redaction.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/store/store.dart';

class Clock {
  DateTime time = DateTime.utc(2026, 10, 23, 12);
  DateTime call() => time;
  void advance(Duration d) => time = time.add(d);
}

({FlutwireEngine engine, MemoryFlutwireStore store, Clock clock}) make([
  FlutwireConfig config = const FlutwireConfig(enabled: true),
]) {
  final clock = Clock();
  final store = MemoryFlutwireStore(notifyInterval: Duration.zero);
  final engine = FlutwireEngine(
    config: config,
    store: store,
    clock: clock.call,
  );
  return (engine: engine, store: store, clock: clock);
}

List<int> utf(String s) => utf8.encode(s);

void main() {
  test('begin publishes a pending call with the secrets already hidden', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'post',
      uri: Uri.parse('https://api.test/items?id=1'),
      source: FlutwireSource.io,
      requestHeaders: FlutwireHeaders.fromMap({
        'Authorization': 'Bearer secret',
        'Accept': 'application/json',
      }),
    )!;
    final call = t.store.find(rec.id)!;
    expect(call.method, 'POST');
    expect(call.state, FlutwireCallState.pending);
    expect(call.request.headers.first('authorization'), '[redacted]');
    expect(call.request.headers.first('accept'), 'application/json');
    expect(call.response, isNull);
  });

  test('a whole exchange ends up in the store', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'POST',
      uri: Uri.parse('https://api.test/items'),
      source: FlutwireSource.dio,
      requestHeaders: FlutwireHeaders.fromMap({
        'content-type': 'application/json',
      }),
    )!;
    rec
      ..requestBody(utf('{"a":'))
      ..requestBody(utf('1}'))
      ..requestSent();
    t.clock.advance(const Duration(milliseconds: 40));
    rec.responseHead(
      statusCode: 201,
      reasonPhrase: 'Created',
      headers: FlutwireHeaders.fromMap({'content-type': 'application/json'}),
      remoteAddress: '203.0.113.9',
      remotePort: 443,
    );
    rec
      ..responseBody(utf('{"id":'))
      ..responseBody(utf('7}'));
    t.clock.advance(const Duration(milliseconds: 60));
    rec.complete();

    final call = t.store.find(rec.id)!;
    expect(call.state, FlutwireCallState.completed);
    expect(call.statusCode, 201);
    expect(call.statusClass, FlutwireStatusClass.success);
    expect(call.request.body.text, '{"a":1}');
    expect(call.response!.body.text, '{"id":7}');
    expect(call.response!.body.jsonValue, {'id': 7});
    expect(call.duration, const Duration(milliseconds: 100));
    expect(call.timeToFirstByte, const Duration(milliseconds: 40));
    expect(call.response!.remoteAddress, '203.0.113.9');
    expect(call.isError, isFalse);
    expect(rec.isFinished, isTrue);
  });

  group('body limits', () {
    FlutwireCall run(int limit, int size) {
      final t = make(FlutwireConfig(enabled: true, maxBodyBytes: limit));
      final rec = t.engine.begin(
        method: 'GET',
        uri: Uri.parse('https://x.test/'),
        source: FlutwireSource.io,
      )!;
      rec.responseHead(
        statusCode: 200,
        headers: FlutwireHeaders.fromMap({'content-type': 'text/plain'}),
      );
      for (var i = 0; i < size; i += 7) {
        rec.responseBody(utf('x' * (size - i < 7 ? size - i : 7)));
      }
      rec.complete();
      return t.store.find(rec.id)!;
    }

    test('keeps the first bytes and counts all of them', () {
      final body = run(10, 25).response!.body;
      expect(body.bytes.length, 10);
      expect(body.totalBytes, 25);
      expect(body.truncated, isTrue);
    });

    test('a body exactly at the limit is whole', () {
      final body = run(10, 10).response!.body;
      expect(body.bytes.length, 10);
      expect(body.truncated, isFalse);
    });

    test('a body under the limit is whole', () {
      final body = run(10, 3).response!.body;
      expect(body.totalBytes, 3);
      expect(body.truncated, isFalse);
    });
  });

  test('a response is hidden by the redaction policy, body included', () {
    final t = make(
      const FlutwireConfig(
        enabled: true,
        redaction: FlutwireRedaction(bodyFields: {'token'}),
      ),
    );
    final rec = t.engine.begin(
      method: 'POST',
      uri: Uri.parse('https://x.test/login'),
      source: FlutwireSource.io,
    )!;
    rec.responseHead(
      statusCode: 200,
      headers: FlutwireHeaders.fromMap({
        'content-type': 'application/json',
        'set-cookie': 'sid=abc',
      }),
    );
    rec
      ..responseBody(utf('{"token":"t0p","user":"a"}'))
      ..complete();
    final res = t.store.find(rec.id)!.response!;
    expect(res.headers.first('set-cookie'), 'sid=[redacted]');
    expect(res.body.text, contains('"token":"[redacted]"'));
    expect(res.body.text, isNot(contains('t0p')));
    expect(res.body.text, contains('"user":"a"'));
  });

  test('a failure keeps what had arrived and the first ending wins', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'GET',
      uri: Uri.parse('https://x.test/'),
      source: FlutwireSource.io,
    )!;
    rec.responseHead(
      statusCode: 200,
      headers: FlutwireHeaders.fromMap({'content-type': 'text/plain'}),
    );
    rec
      ..responseBody(utf('partial'))
      ..fail(const FormatException('boom'), StackTrace.current)
      ..complete()
      ..cancel();
    final call = t.store.find(rec.id)!;
    expect(call.state, FlutwireCallState.failed);
    expect(call.error!.type, 'FormatException');
    expect(call.error!.message, contains('boom'));
    expect(call.response!.body.text, 'partial');
    expect(call.isError, isTrue);
  });

  test('a call that never got a response can fail', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'GET',
      uri: Uri.parse('https://x.test/'),
      source: FlutwireSource.io,
    )!;
    rec.fail(Exception('no route'));
    final call = t.store.find(rec.id)!;
    expect(call.response, isNull);
    expect(call.statusClass, FlutwireStatusClass.none);
    expect(call.state, FlutwireCallState.failed);
  });

  group('done', () {
    FlutwireCallRecorder start() => make().engine.begin(
      method: 'GET',
      uri: Uri.parse('https://api.test/'),
      source: FlutwireSource.io,
    )!;

    test('completes when the call completes', () async {
      final rec = start();
      var done = false;
      unawaited(rec.done.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      rec.complete();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });

    test('completes when the call fails or is cancelled', () async {
      final failed = start()..fail(StateError('down'));
      final cancelled = start()..cancel();

      await expectLater(failed.done, completes);
      await expectLater(cancelled.done, completes);
    });

    test('completes once, however many times the call ends', () async {
      final rec = start()
        ..complete()
        ..fail(StateError('late'))
        ..cancel();

      await expectLater(rec.done, completes);
    });
  });

  test('cancel is its own state', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'GET',
      uri: Uri.parse('https://x.test/'),
      source: FlutwireSource.io,
    )!;
    rec.cancel();
    expect(t.store.find(rec.id)!.state, FlutwireCallState.cancelled);
  });

  test('a GraphQL operation is named once the request is whole', () {
    final t = make();
    final rec = t.engine.begin(
      method: 'POST',
      uri: Uri.parse('https://x.test/graphql'),
      source: FlutwireSource.io,
      requestHeaders: FlutwireHeaders.fromMap({
        'content-type': 'application/json',
      }),
    )!;
    rec
      ..requestBody(
        utf('{"operationName":"Feed","query":"query Feed { items { id } }"}'),
      )
      ..requestSent();
    expect(t.store.find(rec.id)!.graphql?.operationName, 'Feed');
  });

  test('a long response publishes progress, but not on every chunk', () {
    final t = make();
    var published = 0;
    t.store.calls.addListener(() => published++);
    final rec = t.engine.begin(
      method: 'GET',
      uri: Uri.parse('https://x.test/'),
      source: FlutwireSource.io,
    )!;
    rec.responseHead(
      statusCode: 200,
      headers: FlutwireHeaders.fromMap({'content-type': 'text/plain'}),
    );
    t.store.flush();
    final before = published;
    for (var i = 0; i < 200; i++) {
      rec.responseBody(utf('chunk'));
      t.clock.advance(const Duration(milliseconds: 5));
    }
    t.store.flush();
    final during = published - before;
    expect(during, lessThan(10));
    expect(t.store.find(rec.id)!.response!.body.totalBytes, greaterThan(0));
    rec.complete();
    expect(t.store.find(rec.id)!.response!.body.totalBytes, 1000);
  });

  group('whether to record', () {
    test('an ignore rule keeps a call out', () {
      final t = make(
        FlutwireConfig(
          enabled: true,
          ignore: [FlutwireIgnore.host('noise.test')],
        ),
      );
      expect(
        t.engine.begin(
          method: 'GET',
          uri: Uri.parse('https://noise.test/ping'),
          source: FlutwireSource.io,
        ),
        isNull,
      );
      expect(
        t.engine.begin(
          method: 'GET',
          uri: Uri.parse('https://api.test/ping'),
          source: FlutwireSource.io,
        ),
        isNotNull,
      );
    });

    test('pausing stops recording and resuming restarts it', () {
      final t = make();
      Uri uri() => Uri.parse('https://x.test/');
      t.engine.paused.value = true;
      expect(
        t.engine.begin(method: 'GET', uri: uri(), source: FlutwireSource.io),
        isNull,
      );
      t.engine.paused.value = false;
      expect(
        t.engine.begin(method: 'GET', uri: uri(), source: FlutwireSource.io),
        isNotNull,
      );
    });

    test('a configuration that is off records nothing', () {
      final t = make(const FlutwireConfig(enabled: false));
      expect(
        t.engine.begin(
          method: 'GET',
          uri: Uri.parse('https://x.test/'),
          source: FlutwireSource.io,
        ),
        isNull,
      );
    });
  });

  test('ids keep increasing even if the clock stands still', () {
    final t = make();
    final ids = [
      for (var i = 0; i < 5; i++)
        t.engine
            .begin(
              method: 'GET',
              uri: Uri.parse('https://x.test/$i'),
              source: FlutwireSource.io,
            )!
            .id,
    ];
    expect([...ids]..sort(), ids);
    expect(ids.toSet().length, 5);
  });

  test('a failure inside Flutwire never reaches the caller', () {
    final engine = FlutwireEngine(
      config: const FlutwireConfig(enabled: true),
      store: _ExplodingStore(),
    );
    final rec = engine.begin(
      method: 'GET',
      uri: Uri.parse('https://x.test/'),
      source: FlutwireSource.io,
    );
    expect(rec, isNotNull);
    expect(
      () => rec!
        ..requestBody(utf('x'))
        ..responseHead(statusCode: 200, headers: FlutwireHeaders.empty)
        ..responseBody(utf('y'))
        ..complete(),
      returnsNormally,
    );
    expect(engine.internalErrorCount, greaterThan(0));
  });
}

final class _ExplodingStore extends MemoryFlutwireStore {
  @override
  void put(FlutwireCall call) => throw StateError('disk full');
}
