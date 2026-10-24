import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/store/disk_store_io.dart';

final epoch = DateTime.utc(2026, 10, 24, 12);

FlutwireMessage message(
  int index, {
  bool sent = false,
  FlutwireMessageKind kind = FlutwireMessageKind.text,
  List<int>? bytes,
  String? event,
}) => FlutwireMessage(
  index: index,
  sent: sent,
  at: epoch.add(Duration(milliseconds: index * 10)),
  kind: kind,
  bytes: Uint8List.fromList(bytes ?? utf8.encode('message $index')),
  totalBytes: (bytes ?? utf8.encode('message $index')).length,
  event: event,
);

/// A finished WebSocket call that holds [items].
FlutwireCall conversation(
  int id,
  List<FlutwireMessage> items, {
  FlutwireCallState state = FlutwireCallState.completed,
}) => FlutwireCall(
  id: id,
  method: 'GET',
  uri: Uri.parse('wss://api.test/live/$id'),
  source: FlutwireSource.io,
  state: state,
  startedAt: epoch,
  endedAt: state == FlutwireCallState.pending ? null : epoch,
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
  messages: FlutwireMessages(
    kind: FlutwireConversationKind.webSocket,
    items: items,
    total: items.length,
    keptBytes: items.fold(0, (sum, m) => sum + m.bytes.length),
  ),
);

void main() {
  late Directory root;

  Future<DiskFlutwireStore> open([
    FlutwireConfig config = const FlutwireConfig(enabled: true),
  ]) => DiskFlutwireStore.open(
    root,
    config,
    clock: () => epoch,
    notifyInterval: Duration.zero,
  );

  setUp(() => root = Directory.systemTemp.createTempSync('flutwire_messages'));

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File file(int id) => File('${root.path}/messages/$id.jsonl');

  test('the messages of a finished call survive a restart', () async {
    var store = await open();
    store.put(
      conversation(1, [
        message(0, sent: true),
        message(1, kind: FlutwireMessageKind.binary, bytes: [0, 255, 7]),
        message(2, event: 'tick'),
      ]),
    );
    await store.settled;
    await store.dispose();

    store = await open();
    store.flush();
    final summary = store.find(1)!.messages!;
    expect(summary.loaded, isFalse);
    expect(summary.total, 3);
    expect(summary.kind, FlutwireConversationKind.webSocket);
    expect(summary.keptBytes, 9 + 3 + 9);

    final full = (await store.load(1))!.messages!;
    expect(full.loaded, isTrue);
    expect(full.items.map((m) => m.index), [0, 1, 2]);
    expect(full.items[0].sent, isTrue);
    expect(full.items[0].text, 'message 0');
    expect(full.items[1].kind, FlutwireMessageKind.binary);
    expect(full.items[1].bytes, [0, 255, 7]);
    expect(full.items[2].event, 'tick');
    expect(full.items[0].at, epoch);
    await store.dispose();
  });

  test('a conversation that is still open is not written', () async {
    final store = await open();
    store.put(conversation(1, [message(0)], state: FlutwireCallState.pending));
    await store.settled;

    expect(file(1).existsSync(), isFalse);
    await store.dispose();
  });

  test('a call with no messages writes no file for them', () async {
    final store = await open();
    store.put(conversation(1, const []));
    await store.settled;

    expect(file(1).existsSync(), isFalse);
    expect(store.find(1)!.messages!.items, isEmpty);
    await store.dispose();
  });

  test('removing a call removes its messages', () async {
    final store = await open();
    store.put(conversation(1, [message(0)]));
    await store.settled;
    expect(file(1).existsSync(), isTrue);

    await store.remove([1]);
    await store.settled;

    expect(file(1).existsSync(), isFalse);
    await store.dispose();
  });

  test('sweeps messages whose call never made it to disk', () async {
    var store = await open();
    store.put(conversation(1, [message(0)]));
    await store.settled;
    await store.dispose();
    file(9).writeAsStringSync(jsonEncode(message(0).toJson()));

    store = await open();

    expect(file(9).existsSync(), isFalse);
    expect(file(1).existsSync(), isTrue);
    await store.dispose();
  });

  test('skips a line the crash left damaged', () async {
    var store = await open();
    store.put(conversation(1, [message(0), message(1)]));
    await store.settled;
    await store.dispose();
    final lines = file(1).readAsLinesSync();
    file(1).writeAsStringSync('${lines.first}\n{ torn\n${lines.last}\n');

    store = await open();
    final loaded = (await store.load(1))!.messages!;

    expect(loaded.items.map((m) => m.index), [0, 1]);
    await store.dispose();
  });

  test('a call whose file is gone still opens, without its messages', () async {
    var store = await open();
    store.put(conversation(1, [message(0)]));
    await store.settled;
    await store.dispose();
    file(1).deleteSync();

    store = await open();
    final loaded = (await store.load(1))!.messages!;

    expect(loaded.loaded, isTrue);
    expect(loaded.items, isEmpty);
    expect(loaded.total, 1);
    await store.dispose();
  });

  test(
    'memory lets go of the messages of an old call when it runs short',
    () async {
      final store = await open(
        const FlutwireConfig(enabled: true, maxMemoryBytes: 100),
      );
      store.put(conversation(1, [for (var i = 0; i < 20; i++) message(i)]));
      await store.settled;
      store.put(conversation(2, [for (var i = 0; i < 20; i++) message(i)]));
      await store.settled;

      final old = store.find(1)!.messages!;
      expect(old.loaded, isFalse);
      expect(old.total, 20);
      // They are on disk, so opening the call brings them back.
      expect((await store.load(1))!.messages!.items, hasLength(20));
      await store.dispose();
    },
  );

  test('the disk budget counts the messages', () async {
    final store = await open(
      const FlutwireConfig(enabled: true, maxDiskBytes: 300),
    );
    store.put(conversation(1, [for (var i = 0; i < 20; i++) message(i)]));
    await store.settled;
    store.put(conversation(2, [for (var i = 0; i < 20; i++) message(i)]));
    await store.settled;
    // A write sweeps at most every ten minutes, so ask for one by opening again.
    await store.dispose();
    final reopened = await open(
      const FlutwireConfig(enabled: true, maxDiskBytes: 300),
    );
    reopened.flush();

    expect(reopened.calls.value.map((c) => c.id), [2]);
    await reopened.dispose();
  });
}
