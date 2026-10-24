import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/model/message.dart';
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

  group('the layout of the folder', () {
    File marker() => File('${root.path}/layout');

    void copyFixture(String name) {
      final from = Directory('test/fixtures/$name').absolute;
      for (final entity in from.listSync(recursive: true)) {
        final relative = entity.path.substring(from.path.length);
        if (entity is Directory) {
          Directory('${root.path}$relative').createSync(recursive: true);
        } else if (entity is File) {
          File('${root.path}$relative')
            ..createSync(recursive: true)
            ..writeAsBytesSync(entity.readAsBytesSync());
        }
      }
    }

    Map<String, String> snapshot() => {
      for (final file in root.listSync(recursive: true).whereType<File>())
        file.path.substring(root.path.length): base64Encode(
          file.readAsBytesSync(),
        ),
    };

    test('a new folder records its layout and keeps it', () async {
      var store = await open();
      store.put(call(1));
      await store.settled;
      await store.dispose();
      expect(marker().readAsStringSync().trim(), '1');
      store = await open();
      store.flush();
      expect(ids(store), [1]);
      await store.dispose();
    });

    test('a history written by 0.2.0 is read and gets its layout', () async {
      copyFixture('history_0_2_0');
      expect(marker().existsSync(), isFalse);
      final store = await open();
      store.flush();
      expect(ids(store), [6, 5, 4, 3, 2, 1]);
      expect(marker().readAsStringSync().trim(), '1');
      expect(store.preferences.read('themeMode'), 'dark');
      expect(store.preferences.read('dockSide'), 'right');

      final order = (await store.load(1))!;
      expect(order.pinned, isTrue);
      expect(order.request.body.text, '{"items":[{"sku":"A-12","qty":2}]}');
      expect(order.response!.statusCode, 201);
      expect(order.response!.body.text, '{"id":"o-77","total":42}');
      expect(order.response!.remoteAddress, '203.0.113.7');

      final club = (await store.load(2))!;
      expect(club.source, FlutwireSource.dio);
      expect(club.response!.body.text, 'no such club');
      expect(club.response!.compression, 'gzip');
      expect(club.response!.redirects.single.statusCode, 301);
      expect(club.response!.certificate!.subject, 'CN=api.example.com');

      final failed = (await store.load(3))!;
      expect(failed.state, FlutwireCallState.failed);
      expect(failed.error!.message, 'Connection reset by peer');
      expect(failed.graphql!.operationName, 'Clubs');
      expect(failed.request.body.text, contains('query Clubs'));

      final socket = (await store.load(4))!;
      expect(socket.messages!.kind, FlutwireConversationKind.webSocket);
      expect(socket.messages!.total, 3);
      expect(socket.messages!.items.map((m) => m.kind), [
        FlutwireMessageKind.text,
        FlutwireMessageKind.binary,
        FlutwireMessageKind.close,
      ]);
      expect(socket.messages!.items.first.text, '{"hello":"server"}');
      expect(socket.messages!.items.first.sent, isTrue);

      final again = (await store.load(5))!;
      expect(again.resentFrom, 1);
      expect(again.intercept, FlutwireIntercept.edited);

      // A summary from 0.1.0 has no field for any of the above.
      final health = (await store.load(6))!;
      expect(health.response!.statusCode, 200);
      expect(health.response!.body.text, 'ok');
      expect(health.resentFrom, isNull);
      expect(health.intercept, isNull);
      expect(health.messages, isNull);
      await store.dispose();
    });

    test('a folder of a newer layout is left as it is', () async {
      copyFixture('history_0_2_0');
      marker().writeAsStringSync('2\n');
      File('${root.path}/calls/7.json').writeAsStringSync('{"v":2,"x":[]}');
      File('${root.path}/bodies/7.res').writeAsStringSync('from the future');
      final before = snapshot();

      await expectLater(open(), throwsFormatException);
      expect(snapshot(), before);

      final store = await openStore(
        FlutwireConfig(enabled: true, storagePath: root.path),
      );
      expect(store, isNot(isA<DiskFlutwireStore>()));
      expect(ids(store as MemoryFlutwireStore), isEmpty);
      await store.dispose();
      expect(snapshot(), before);
    });

    for (final text in ['', 'two', '0', '-1', '1.5']) {
      test('a layout of "$text" is left as it is', () async {
        copyFixture('history_0_2_0');
        marker().writeAsStringSync(text);
        final before = snapshot();
        await expectLater(open(), throwsFormatException);
        expect(snapshot(), before);
      });
    }
  });
}
