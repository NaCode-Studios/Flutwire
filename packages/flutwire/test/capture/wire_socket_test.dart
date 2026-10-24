// The sockets here stand in for ones an app closes, so none of them is.
// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/capture/wire/wire_socket.dart';
import 'package:flutwire/src/engine.dart';

import '../support/websocket_frames.dart';

/// A socket that does what a test tells it to, and answers nothing else.
class FakeSocket extends Stream<Uint8List> implements Socket {
  final StreamController<Uint8List> incoming = StreamController<Uint8List>();
  final Completer<void> writing = Completer<void>();
  final List<List<int>> written = [];
  bool destroyed = false;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(List<int> data) => written.add(data);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      stream.forEach(written.add);

  @override
  Future<dynamic> get done => writing.future;

  @override
  void destroy() => destroyed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Uint8List bytes(List<int> data) => Uint8List.fromList(data);

void main() {
  late FlutwireEngine engine;
  late MemoryFlutwireStore store;
  late FlutwireCallRecorder recorder;
  late FakeSocket fake;
  late WireSocket socket;
  late List<Uint8List> seen;
  late List<Object> errors;

  setUp(() {
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    engine = FlutwireEngine(
      config: const FlutwireConfig(enabled: true),
      store: store,
    );
    recorder = engine.begin(
      method: 'GET',
      uri: Uri.parse('wss://api.test/live'),
      source: FlutwireSource.io,
    )!;
    fake = FakeSocket();
    socket = WireSocket(fake, recorder);
    seen = [];
    errors = [];
    socket.listen(seen.add, onError: errors.add);
  });

  tearDown(() => fake.incoming.close());

  FlutwireCall call() => store.find(recorder.id)!;

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('hands the bytes on untouched, in both directions', () async {
    final server = frame(1, utf8.encode('from the server'));
    final client = frame(1, utf8.encode('from the app'), masked: true);

    fake.incoming.add(server);
    socket.add(client);
    await pump();

    expect(seen.single, server);
    expect(fake.written.single, client);
  });

  test('lists the messages that crossed, each with its direction', () async {
    fake.incoming.add(frame(1, utf8.encode('down')));
    await pump();
    socket.add(frame(1, utf8.encode('up'), masked: true));
    recorder.complete();

    final items = call().messages!.items;
    expect(items.map((m) => (m.sent, m.text)), [(false, 'down'), (true, 'up')]);
  });

  test('reads the frames of an addStream the way it reads add', () async {
    final done = socket.addStream(
      Stream.fromIterable([
        frame(2, [7, 7, 7], masked: true),
      ]),
    );
    await done;
    recorder.complete();

    expect(call().messages!.items.single.bytes, [7, 7, 7]);
  });

  test('says the call holds a WebSocket from the start', () {
    expect(call().messages!.kind, FlutwireConversationKind.webSocket);
    expect(call().isPending, isTrue);
  });

  test('keeps passing bytes it cannot read, and lists nothing', () async {
    fake.incoming.add(bytes([0xA1, 0x00, 1, 2, 3]));
    fake.incoming.add(frame(1, utf8.encode('after')));
    await pump();

    expect(seen, hasLength(2));
    expect(call().messages!.items, isEmpty);
    expect(call().isPending, isTrue);
  });

  group('the call ends', () {
    test('when the other side stops sending', () async {
      await fake.incoming.close();
      await pump();

      expect(call().state, FlutwireCallState.completed);
    });

    test('as failed when the connection breaks', () async {
      fake.incoming.addError(const SocketException('reset by peer'));
      await pump();

      expect(call().state, FlutwireCallState.failed);
      expect(call().error!.type, 'SocketException');
      expect(errors.single, isA<SocketException>());
    });

    test('as failed when writing fails', () async {
      fake.writing.completeError(const SocketException('broken pipe'));
      await pump();

      expect(call().state, FlutwireCallState.failed);
    });

    test('when the app destroys the socket', () {
      socket.destroy();

      expect(fake.destroyed, isTrue);
      expect(call().state, FlutwireCallState.completed);
    });

    test('once each side has said goodbye', () async {
      socket.add(frame(8, [0x03, 0xe8], masked: true));
      await pump();

      expect(call().isPending, isTrue);

      fake.incoming.add(frame(8, [0x03, 0xe8]));
      await pump();

      expect(call().state, FlutwireCallState.completed);
      expect(call().messages!.items.map((m) => m.kind), [
        FlutwireMessageKind.close,
        FlutwireMessageKind.close,
      ]);
    });

    test('not when only the writing side is closed', () async {
      fake.writing.complete();
      await pump();

      expect(call().isPending, isTrue);
    });
  });
}
