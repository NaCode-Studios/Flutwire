// These tests open real WebSockets and event streams against a server on the
// loopback interface, through the clients the SDK ships. They avoid the widget
// test binding, which replaces every HttpClient with one that refuses to
// connect.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/capture/wire/wire_io.dart';
import 'package:flutwire/src/engine.dart';

late HttpServer server;
late String host;

Future<void> handle(HttpRequest req) async {
  try {
    switch (req.uri.path) {
      case '/ws':
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((message) {
          if (message is String) {
            ws.add('echo:$message');
          } else {
            ws.add(message as List<int>);
          }
        }, onDone: ws.close);
      case '/plain':
        final ws = await WebSocketTransformer.upgrade(
          req,
          compression: CompressionOptions.compressionOff,
        );
        ws.listen((message) => ws.add('echo:$message'), onDone: ws.close);
      case '/sse':
        req.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        req.response.write('data: first\n\n');
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        req.response.write('event: tick\nid: 2\ndata: {"n":2}\n\n');
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await req.response.close();
      default:
        req.response.statusCode = 404;
        await req.response.close();
    }
  } on Object {
    // The client walked away, which some of the tests do on purpose.
  }
}

/// A WebSocket with the one listener an app has, which keeps it reading: dart:io
/// holds a socket nobody listens to, and it reads nothing, not even a pong.
class Connection {
  Connection(this.socket) {
    socket.listen(
      inbox.add,
      onDone: () => closed.complete(),
      onError: (Object _) {},
    );
  }

  final WebSocket socket;
  final List<Object?> inbox = [];
  final Completer<void> closed = Completer<void>();

  /// Waits until [count] messages have come from the server.
  Future<void> received(int count) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (inbox.length < count) {
      if (DateTime.now().isAfter(end)) fail('Only ${inbox.length} messages.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Closes the way an app does, and waits for the other side to answer.
  Future<void> close([int? code, String? reason]) async {
    await socket.close(code, reason);
    await closed.future.timeout(const Duration(seconds: 5));
  }
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    host = '127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close(force: true));

  late MemoryFlutwireStore store;
  late FlutwireEngine engine;
  late void Function() uninstall;

  void start([FlutwireConfig config = const FlutwireConfig(enabled: true)]) {
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    engine = FlutwireEngine(config: config, store: store);
    uninstall = installWireCapture(engine);
  }

  tearDown(() {
    uninstall();
    HttpOverrides.global = null;
  });

  FlutwireCall only() => store.calls.value.single;

  /// Opens a WebSocket through a client made after the capture was installed,
  /// and closes that client once the handshake is over, as apps do. The shared
  /// client of `WebSocket.connect` may be older than the capture: the test
  /// runner opens a WebSocket of its own before any test starts.
  Future<Connection> connect(
    String path, {
    CompressionOptions compression = CompressionOptions.compressionDefault,
  }) async {
    final client = HttpClient();
    // The connection returned closes it.
    // ignore: close_sinks
    final socket = await WebSocket.connect(
      'ws://$host$path',
      compression: compression,
      customClient: client,
    );
    client.close();
    return Connection(socket);
  }

  /// Waits until the one call is over, however it ended.
  Future<FlutwireCall> finished() async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      store.flush();
      final calls = store.calls.value;
      if (calls.length == 1 && !calls.single.isPending) return calls.single;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('The call did not finish.');
  }

  String describe(FlutwireMessage m) =>
      '${m.sent ? 'sent' : 'got'} ${m.kind.name} ${m.text ?? m.bytes}';

  test('a WebSocket lists what crossed it, in both directions', () async {
    start();
    final connection = await connect('/ws');
    connection.socket
      ..add('hello')
      ..add(Uint8List.fromList([1, 2, 3]));
    await connection.received(2);
    await connection.close(1000, 'done');
    final call = await finished();

    expect(call.statusCode, 101);
    expect(call.uri.scheme, 'ws');
    expect(call.uri.path, '/ws');
    expect(call.state, FlutwireCallState.completed);
    expect(call.messages!.kind, FlutwireConversationKind.webSocket);
    final items = call.messages!.items;
    expect(
      items.map(describe),
      containsAllInOrder(['sent text hello', 'got text echo:hello']),
    );
    expect(
      items.map(describe),
      containsAll(['sent binary [1, 2, 3]', 'got binary [1, 2, 3]']),
    );
    final closes = items.where((m) => m.kind == FlutwireMessageKind.close);
    expect(closes.map((m) => m.sent), containsAll([true, false]));
    final sentClose = closes.firstWhere((m) => m.sent);
    expect(sentClose.closeCode, 1000);
    expect(sentClose.closeReason, 'done');
    expect(
      items.map((m) => m.index),
      orderedEquals(List.generate(items.length, (i) => i)),
    );
    expect(call.messages!.total, items.length);
  });

  test('the call stays open for as long as the connection does', () async {
    start();
    final connection = await connect('/ws');
    connection.socket.add('ping');
    await connection.received(1);
    // Messages reach the store in bursts, a moment after they cross.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    store.flush();

    expect(only().isPending, isTrue);
    expect(only().messages!.items.map(describe), [
      'sent text ping',
      'got text echo:ping',
    ]);

    await connection.close();
    expect((await finished()).state, FlutwireCallState.completed);
  });

  test('compressed messages are read, in both directions', () async {
    start();
    final text = 'a long line that repeats, ' * 200;
    final connection = await connect('/ws');
    connection.socket.add(text);
    await connection.received(1);
    await connection.close();
    final call = await finished();

    expect(
      call.response!.headers.first('sec-websocket-extensions'),
      contains('permessage-deflate'),
    );
    final texts = call.messages!.items.where(
      (m) => m.kind == FlutwireMessageKind.text,
    );
    expect(texts.map((m) => m.text), [text, 'echo:$text']);
    expect(texts.every((m) => !m.undecoded), isTrue);
    expect(texts.first.totalBytes, utf8.encode(text).length);
  });

  test('messages are read when the connection is not compressed', () async {
    start();
    final connection = await connect(
      '/plain',
      compression: CompressionOptions.compressionOff,
    );
    connection.socket.add('plain');
    await connection.received(1);
    await connection.close();
    final call = await finished();

    expect(
      call.response!.headers.contains('sec-websocket-extensions'),
      isFalse,
    );
    expect(
      call.messages!.items
          .where((m) => m.kind == FlutwireMessageKind.text)
          .map((m) => m.text),
      ['plain', 'echo:plain'],
    );
  });

  test('pings and pongs are listed', () async {
    start();
    final connection = await connect('/ws');
    connection.socket.pingInterval = const Duration(milliseconds: 40);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await connection.close();
    final call = await finished();

    final kinds = call.messages!.items.map((m) => (m.kind, m.sent));
    expect(kinds, contains((FlutwireMessageKind.ping, true)));
    expect(kinds, contains((FlutwireMessageKind.pong, false)));
  });

  test('a WebSocket that is not recorded works all the same', () async {
    start();
    engine.paused.value = true;
    final connection = await connect('/ws');
    connection.socket.add('quiet');
    await connection.received(1);
    expect(connection.inbox.single, 'echo:quiet');
    await connection.close();

    expect(store.calls.value, isEmpty);
  });

  test(
    'an event stream lists its events and stays a normal response',
    () async {
      start();
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://$host/sse'));
      final response = await request.close();
      final seen = <String>[];
      await response.transform(utf8.decoder).forEach(seen.add);
      client.close();
      final call = await finished();

      expect(call.statusCode, 200);
      expect(call.messages!.kind, FlutwireConversationKind.eventStream);
      final [first, second] = call.messages!.items;
      expect(first.text, 'first');
      expect(first.event, isNull);
      expect(second.event, 'tick');
      expect(second.eventId, '2');
      expect(second.text, '{"n":2}');
      expect(second.at.isAfter(first.at), isTrue);
      expect(call.response!.body.text, seen.join());
    },
  );
}
