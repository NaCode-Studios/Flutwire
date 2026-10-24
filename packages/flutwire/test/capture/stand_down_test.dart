import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/redaction.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/coverage.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/store/store.dart';

class Clock {
  DateTime time = DateTime.utc(2026, 10, 24, 12);
  DateTime call() => time;
  void advance(Duration d) => time = time.add(d);
}

({FlutwireEngine engine, Clock clock}) make({
  FlutwireConfig config = const FlutwireConfig(enabled: true),
  bool capture = true,
}) {
  final clock = Clock();
  final engine = FlutwireEngine(
    config: config,
    store: MemoryFlutwireStore(notifyInterval: Duration.zero),
    clock: clock.call,
  );
  engine.wireCaptureActive = capture;
  return (engine: engine, clock: clock);
}

final items = Uri.parse('https://api.test/items');

void main() {
  group('an adapter stands down for the dart:io capture', () {
    test('and there is nothing to watch without the capture', () {
      final t = make(capture: false);

      expect(
        t.engine.watchStandDown(method: 'GET', uri: items, client: 'Dio'),
        isNull,
      );
    });

    test('nor while paused, nor for a call that is ignored', () {
      final paused = make();
      paused.engine.paused.value = true;
      expect(
        paused.engine.watchStandDown(method: 'GET', uri: items, client: 'Dio'),
        isNull,
      );

      final ignored = make(
        config: FlutwireConfig(
          enabled: true,
          ignore: [FlutwireIgnore.host('api.test')],
        ),
      );
      expect(
        ignored.engine.watchStandDown(method: 'GET', uri: items, client: 'Dio'),
        isNull,
      );
    });

    test('and says nothing when the capture saw the call', () {
      final t = make();
      final watch = t.engine.watchStandDown(
        method: 'get',
        uri: items,
        client: 'Dio',
      )!;
      t.clock.advance(const Duration(milliseconds: 5));
      t.engine.begin(method: 'GET', uri: items, source: FlutwireSource.io);
      t.clock.advance(const Duration(milliseconds: 80));

      watch.finish();

      expect(t.engine.coverage.notes.value, isEmpty);
    });

    test('and says so when the capture never saw it', () {
      final t = make();
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: items,
        client: 'FlutwireClient over CronetClient',
      )!;
      t.clock.advance(const Duration(milliseconds: 80));

      watch.finish();

      final note = t.engine.coverage.notes.value.single;
      expect(note.gap, FlutwireGap.clientBypassesDartIo);
      expect(note.subject, 'FlutwireClient over CronetClient · api.test');
      expect(note.count, 1);
    });

    test('and counts each call the capture missed', () {
      final t = make();
      for (var i = 0; i < 3; i++) {
        t.engine
            .watchStandDown(method: 'GET', uri: items, client: 'Dio')!
            .finish();
        t.clock.advance(const Duration(seconds: 1));
      }

      expect(t.engine.coverage.notes.value.single.count, 3);
    });

    test('a call the capture began earlier does not count', () {
      final t = make();
      t.engine.begin(method: 'GET', uri: items, source: FlutwireSource.io);
      t.clock.advance(const Duration(seconds: 2));
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: items,
        client: 'Dio',
      )!;

      watch.finish();

      expect(t.engine.coverage.notes.value, hasLength(1));
    });

    test('a call to another address, or by another method, does not count', () {
      final t = make();
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: items,
        client: 'Dio',
      )!;
      t.engine.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test/other'),
        source: FlutwireSource.io,
      );
      t.engine.begin(method: 'POST', uri: items, source: FlutwireSource.io);

      watch.finish();

      expect(t.engine.coverage.notes.value, hasLength(1));
    });

    test('and a call another adapter recorded does not count either', () {
      final t = make();
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: items,
        client: 'Dio',
      )!;
      t.engine.begin(method: 'GET', uri: items, source: FlutwireSource.dio);

      watch.finish();

      expect(t.engine.coverage.notes.value, hasLength(1));
    });

    test('and the call is found through the redaction of its address', () {
      final t = make(
        config: const FlutwireConfig(
          enabled: true,
          redaction: FlutwireRedaction(queryParameters: {'api_key'}),
        ),
      );
      final uri = Uri.parse('https://api.test/items?api_key=abc&page=2');
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: uri,
        client: 'Dio',
      )!;
      t.engine.begin(method: 'GET', uri: uri, source: FlutwireSource.io);

      watch.finish();

      expect(t.engine.coverage.notes.value, isEmpty);
    });

    test('blames the capture, not the client, when the capture is gone', () {
      final t = make();
      t.engine.wireCaptureProbe = () => false;
      final watch = t.engine.watchStandDown(
        method: 'GET',
        uri: items,
        client: 'Dio',
      )!;

      watch.finish();

      final note = t.engine.coverage.notes.value.single;
      expect(note.gap, FlutwireGap.captureReplaced);
    });
  });

  group('checking the capture', () {
    test('finds nothing wrong without a capture to check', () {
      final t = make();

      expect(t.engine.verifyCapture(), isTrue);
      expect(t.engine.coverage.notes.value, isEmpty);
    });

    test('notes a capture that is gone and forgets it when it is back', () {
      final t = make();
      var intact = false;
      t.engine.wireCaptureProbe = () => intact;

      expect(t.engine.verifyCapture(), isFalse);
      expect(
        t.engine.coverage.notes.value.single.gap,
        FlutwireGap.captureReplaced,
      );

      intact = true;
      expect(t.engine.verifyCapture(), isTrue);
      expect(t.engine.coverage.notes.value, isEmpty);
    });

    test('a probe that throws is taken as nothing wrong', () {
      final t = make();
      t.engine.wireCaptureProbe = () => throw StateError('no');

      expect(t.engine.verifyCapture(), isTrue);
      expect(t.engine.coverage.notes.value, isEmpty);
    });
  });
}
