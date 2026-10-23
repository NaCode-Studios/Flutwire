import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/store/store.dart';

FlutwireCall call(int id, {int bodyBytes = 0, bool pinned = false}) =>
    FlutwireCall(
      id: id,
      method: 'GET',
      uri: Uri.parse('https://x.test/$id'),
      source: FlutwireSource.io,
      startedAt: DateTime.utc(2026, 10, 23).add(Duration(seconds: id)),
      pinned: pinned,
      request: FlutwireRequest(
        headers: FlutwireHeaders.empty,
        body: FlutwireBody(bytes: Uint8List(bodyBytes)),
      ),
    );

List<int> ids(MemoryFlutwireStore s) => [for (final c in s.calls.value) c.id];

void main() {
  late MemoryFlutwireStore store;

  setUp(() => store = MemoryFlutwireStore(notifyInterval: Duration.zero));
  tearDown(() => store.dispose());

  test('lists the newest call first', () {
    store
      ..put(call(1))
      ..put(call(3))
      ..put(call(2))
      ..flush();
    expect(ids(store), [3, 2, 1]);
  });

  test('replaces a call with the same id instead of adding one', () {
    store
      ..put(call(1))
      ..put(call(1).copyWith(state: FlutwireCallState.completed))
      ..flush();
    expect(store.length, 1);
    expect(store.find(1)!.state, FlutwireCallState.completed);
  });

  test('drops the oldest calls past the limit', () {
    store = MemoryFlutwireStore(maxCalls: 3, notifyInterval: Duration.zero);
    for (var i = 1; i <= 5; i++) {
      store.put(call(i));
    }
    store.flush();
    expect(ids(store), [5, 4, 3]);
  });

  test('a pinned call outlives the limit but still counts against it', () {
    store = MemoryFlutwireStore(maxCalls: 2, notifyInterval: Duration.zero);
    store
      ..put(call(1, pinned: true))
      ..put(call(2))
      ..put(call(3))
      ..put(call(4))
      ..flush();
    expect(ids(store), [4, 1]);
  });

  test('releases the oldest bodies when memory runs out', () {
    store = MemoryFlutwireStore(maxBytes: 100, notifyInterval: Duration.zero);
    store
      ..put(call(1, bodyBytes: 60))
      ..put(call(2, bodyBytes: 60))
      ..put(call(3, bodyBytes: 60))
      ..flush();
    expect(ids(store), [3]);
    expect(store.memoryBytes, 60);
  });

  test('never drops the call that was just added', () {
    store = MemoryFlutwireStore(maxBytes: 10, notifyInterval: Duration.zero);
    store
      ..put(call(1, bodyBytes: 500))
      ..flush();
    expect(ids(store), [1]);
  });

  test('clear keeps pinned calls unless told otherwise', () async {
    store
      ..put(call(1, pinned: true))
      ..put(call(2));
    await store.clear();
    store.flush();
    expect(ids(store), [1]);
    await store.clear(keepPinned: false);
    store.flush();
    expect(ids(store), isEmpty);
  });

  test('remove takes out the named calls only', () async {
    store
      ..put(call(1))
      ..put(call(2))
      ..put(call(3));
    await store.remove([1, 3, 99]);
    store.flush();
    expect(ids(store), [2]);
  });

  test('pinning is reflected in the list', () async {
    store.put(call(1));
    await store.setPinned([1], pinned: true);
    store.flush();
    expect(store.calls.value.single.pinned, isTrue);
    await store.setPinned([1], pinned: false);
    store.flush();
    expect(store.calls.value.single.pinned, isFalse);
  });

  test('load returns the call', () async {
    store.put(call(1));
    expect((await store.load(1))!.id, 1);
    expect(await store.load(2), isNull);
  });

  test('folds a burst of changes into a few notifications', () async {
    store = MemoryFlutwireStore(
      notifyInterval: const Duration(milliseconds: 60),
    );
    var notifications = 0;
    store.calls.addListener(() => notifications++);
    for (var i = 1; i <= 100; i++) {
      store.put(call(i));
    }
    expect(notifications, 1, reason: 'the first change is shown at once');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(notifications, 2, reason: 'the rest arrive together');
    expect(store.calls.value.length, 100);
  });

  test('ignores writes after it was disposed', () async {
    await store.dispose();
    expect(() => store.put(call(1)), returnsNormally);
    expect(store.length, 0);
  });
}
