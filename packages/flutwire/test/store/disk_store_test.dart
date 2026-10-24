import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/store/disk_store_io.dart';
import 'package:flutwire/src/store/open_store.dart';
import 'package:flutwire/src/store/store.dart';

final epoch = DateTime.utc(2026, 10, 23, 12);

FlutwireCall call(
  int id, {
  DateTime? at,
  int bodyBytes = 10,
  bool pinned = false,
  FlutwireCallState state = FlutwireCallState.completed,
}) {
  final started = at ?? epoch;
  return FlutwireCall(
    id: id,
    method: 'POST',
    uri: Uri.parse('https://api.test/items/$id'),
    source: FlutwireSource.io,
    state: state,
    startedAt: started,
    endedAt: state == FlutwireCallState.pending
        ? null
        : started.add(const Duration(milliseconds: 50)),
    pinned: pinned,
    request: FlutwireRequest(
      headers: FlutwireHeaders.fromMap({'content-type': 'application/json'}),
      body: FlutwireBody(
        bytes: Uint8List.fromList(utf8.encode('{"id":$id}')),
        contentType: 'application/json',
      ),
    ),
    response: FlutwireResponse(
      statusCode: 200,
      headers: FlutwireHeaders.fromMap({'content-type': 'text/plain'}),
      body: FlutwireBody(
        bytes: Uint8List(bodyBytes)..fillRange(0, bodyBytes, 65),
        contentType: 'text/plain',
      ),
    ),
  );
}

void main() {
  late Directory root;
  var now = epoch;

  Future<DiskFlutwireStore> open([
    FlutwireConfig config = const FlutwireConfig(enabled: true),
  ]) => DiskFlutwireStore.open(
    root,
    config,
    clock: () => now,
    notifyInterval: Duration.zero,
  );

  List<int> ids(MemoryFlutwireStore s) => [for (final c in s.calls.value) c.id];

  setUp(() {
    root = Directory.systemTemp.createTempSync('flutwire_disk_test');
    now = epoch;
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a finished call survives a restart, bodies included', () async {
    var store = await open();
    store.put(call(1));
    await store.settled;
    await store.dispose();

    store = await open();
    store.flush();
    expect(ids(store), [1]);
    final summary = store.find(1)!;
    expect(summary.request.body.loaded, isFalse);
    expect(summary.response!.body.totalBytes, 10);
    final full = (await store.load(1))!;
    expect(full.request.body.text, '{"id":1}');
    expect(full.response!.body.text, 'AAAAAAAAAA');
    expect(full.uri.path, '/items/1');
    await store.dispose();
  });

  test('a call still in flight is not written', () async {
    final store = await open();
    store.put(call(1, state: FlutwireCallState.pending));
    await store.settled;
    expect(Directory('${root.path}/calls').listSync(), isEmpty);
    await store.dispose();
  });

  test('sweeps what a crash left behind', () async {
    var store = await open();
    store.put(call(1));
    await store.settled;
    await store.dispose();

    File('${root.path}/calls/2.json').writeAsStringSync('{ not json');
    File('${root.path}/calls/3.json.tmp').writeAsStringSync('{}');
    File('${root.path}/bodies/9.res').writeAsBytesSync([1, 2, 3]);

    store = await open();
    store.flush();
    expect(ids(store), [1]);
    expect(File('${root.path}/calls/2.json').existsSync(), isFalse);
    expect(File('${root.path}/calls/3.json.tmp').existsSync(), isFalse);
    expect(File('${root.path}/bodies/9.res').existsSync(), isFalse);
    expect(File('${root.path}/bodies/1.res').existsSync(), isTrue);
    await store.dispose();
  });

  test(
    'forgets calls older than the retention period but keeps pinned ones',
    () async {
      var store = await open();
      store
        ..put(call(1, at: epoch.subtract(const Duration(days: 3))))
        ..put(
          call(2, at: epoch.subtract(const Duration(days: 3)), pinned: true),
        )
        ..put(call(3, at: epoch.subtract(const Duration(hours: 2))));
      await store.settled;
      await store.dispose();

      store = await open(
        const FlutwireConfig(
          enabled: true,
          retention: FlutwireRetention.oneDay,
        ),
      );
      await store.settled;
      store.flush();
      expect(ids(store), [3, 2]);
      expect(File('${root.path}/calls/1.json').existsSync(), isFalse);
      expect(File('${root.path}/bodies/1.res').existsSync(), isFalse);
      expect(File('${root.path}/calls/2.json').existsSync(), isTrue);
      await store.dispose();
    },
  );

  test('retention forever keeps everything', () async {
    var store = await open();
    store.put(call(1, at: epoch.subtract(const Duration(days: 400))));
    await store.settled;
    await store.dispose();
    store = await open(
      const FlutwireConfig(enabled: true, retention: FlutwireRetention.forever),
    );
    store.flush();
    expect(ids(store), [1]);
    await store.dispose();
  });

  test(
    'stays inside the disk budget by dropping the oldest unpinned calls',
    () async {
      var store = await open();
      for (var i = 1; i <= 5; i++) {
        store.put(
          call(i, at: epoch.add(Duration(minutes: i)), bodyBytes: 1000),
        );
      }
      await store.settled;
      await store.dispose();

      // Each call keeps about 1,008 bytes of body.
      store = await open(
        const FlutwireConfig(enabled: true, maxDiskBytes: 2500),
      );
      await store.settled;
      store.flush();
      expect(ids(store), [5, 4]);
      await store.dispose();
    },
  );

  test('removing and clearing delete the files', () async {
    final store = await open();
    store
      ..put(call(1))
      ..put(call(2))
      ..put(call(3, pinned: true));
    await store.settled;
    await store.remove([1]);
    await store.settled;
    expect(File('${root.path}/calls/1.json').existsSync(), isFalse);
    expect(File('${root.path}/bodies/1.req').existsSync(), isFalse);

    await store.clear();
    await store.settled;
    expect(File('${root.path}/calls/2.json').existsSync(), isFalse);
    expect(File('${root.path}/calls/3.json').existsSync(), isTrue);
    await store.dispose();
  });

  test('pinning is remembered across a restart', () async {
    var store = await open();
    store.put(call(1));
    await store.setPinned([1], pinned: true);
    await store.settled;
    await store.dispose();

    store = await open();
    store.flush();
    expect(store.find(1)!.pinned, isTrue);
    await store.dispose();
  });

  test(
    'memory pressure releases the bodies of saved calls and they load again',
    () async {
      final store = await open(
        const FlutwireConfig(enabled: true, maxMemoryBytes: 150),
      );
      store.put(call(1, bodyBytes: 100));
      await store.settled;
      store.put(call(2, bodyBytes: 100));
      await store.settled;
      store.flush();

      expect(ids(store), [2, 1], reason: 'both calls are still listed');
      expect(store.find(1)!.response!.body.loaded, isFalse);
      expect(store.find(2)!.response!.body.loaded, isTrue);
      final back = (await store.load(1))!;
      expect(back.response!.body.bytes, hasLength(100));
      expect(back.response!.body.kind, FlutwireBodyKind.text);
      await store.dispose();
    },
  );

  test('openStore falls back to memory when persistence is off', () async {
    final store = await openStore(
      const FlutwireConfig(enabled: true, persist: false),
    );
    expect(store, isA<MemoryFlutwireStore>());
    expect(store, isNot(isA<DiskFlutwireStore>()));
    await store.dispose();
  });

  test('openStore uses the folder it is told to', () async {
    final store = await openStore(
      FlutwireConfig(enabled: true, storagePath: root.path),
    );
    expect(store, isA<DiskFlutwireStore>());
    await store.dispose();
  });

  test('openStore falls back to memory when the folder is unusable', () async {
    final blocker = File('${root.path}/blocker')..writeAsStringSync('x');
    final store = await openStore(
      FlutwireConfig(enabled: true, storagePath: '${blocker.path}/sub'),
    );
    expect(store, isNot(isA<DiskFlutwireStore>()));
    await store.dispose();
  });
}
