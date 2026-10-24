import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/engine.dart';

({FlutwireEngine engine, MemoryFlutwireStore store}) make([
  FlutwireConfig config = const FlutwireConfig(enabled: true),
]) {
  final store = MemoryFlutwireStore(notifyInterval: Duration.zero);
  return (engine: FlutwireEngine(config: config, store: store), store: store);
}

FlutwireCallRecorder begin(FlutwireEngine engine) => engine.begin(
  method: 'GET',
  uri: Uri.parse('https://api.test/live'),
  source: FlutwireSource.io,
)!;

List<int> utf(String text) => utf8.encode(text);

FlutwireHeaders headers(String contentType) =>
    FlutwireHeaders.fromMap({'content-type': contentType});

void main() {
  group('the messages of a call', () {
    test('keep their direction, kind and size', () {
      final t = make();
      final rec = begin(t.engine);

      rec
        ..message(
          sent: true,
          kind: FlutwireMessageKind.text,
          payload: utf('hi'),
        )
        ..message(
          sent: false,
          kind: FlutwireMessageKind.binary,
          payload: [1, 2, 3],
        )
        ..complete();

      final messages = t.store.find(rec.id)!.messages!;
      expect(messages.kind, FlutwireConversationKind.webSocket);
      expect(messages.total, 2);
      final [first, second] = messages.items;
      expect(first.sent, isTrue);
      expect(first.kind, FlutwireMessageKind.text);
      expect(first.text, 'hi');
      expect(first.index, 0);
      expect(second.sent, isFalse);
      expect(second.bytes, [1, 2, 3]);
      expect(second.index, 1);
    });

    test('are an empty list once the call says it holds a conversation', () {
      final t = make();
      final rec = begin(t.engine);

      rec.startConversation(FlutwireConversationKind.webSocket);

      final messages = t.store.find(rec.id)!.messages!;
      expect(messages.items, isEmpty);
      expect(messages.total, 0);
    });

    test('give a WebSocket the address the app wrote', () {
      final t = make();
      final rec = t.engine.begin(
        method: 'GET',
        uri: Uri.parse('https://echo.test:0#'),
        source: FlutwireSource.io,
      )!;

      rec.startConversation(FlutwireConversationKind.webSocket);

      expect(t.store.find(rec.id)!.uri.toString(), 'wss://echo.test/');
    });

    test('keep the port, the path and the query of a WebSocket address', () {
      final t = make();
      final rec = t.engine.begin(
        method: 'GET',
        uri: Uri.parse('http://user:pw@echo.test:8080/live?room=7'),
        source: FlutwireSource.io,
      )!;

      rec.startConversation(FlutwireConversationKind.webSocket);

      expect(
        t.store.find(rec.id)!.uri.toString(),
        'ws://user:pw@echo.test:8080/live?room=7',
      );
    });

    test('leave the address of an event stream as it was', () {
      final t = make();
      final rec = t.engine.begin(
        method: 'GET',
        uri: Uri.parse('https://api.test/stream?x=1'),
        source: FlutwireSource.io,
      )!;

      rec.startConversation(FlutwireConversationKind.eventStream);

      expect(
        t.store.find(rec.id)!.uri.toString(),
        'https://api.test/stream?x=1',
      );
    });

    test('are absent from an ordinary call', () {
      final t = make();
      final rec = begin(t.engine)..complete();

      expect(t.store.find(rec.id)!.messages, isNull);
    });

    test('are cut at the body limit, and the real size is kept', () {
      final t = make(const FlutwireConfig(enabled: true, maxBodyBytes: 10));
      final rec = begin(t.engine);

      rec
        ..message(
          sent: false,
          kind: FlutwireMessageKind.text,
          payload: utf('x' * 100),
        )
        ..complete();

      final message = t.store.find(rec.id)!.messages!.items.single;
      expect(message.bytes, hasLength(10));
      expect(message.totalBytes, 100);
      expect(message.truncated, isTrue);
    });

    test('are the size a frame reader reported, when it says so', () {
      final t = make();
      final rec = begin(t.engine);

      rec
        ..message(
          sent: false,
          kind: FlutwireMessageKind.text,
          payload: utf('start'),
          totalBytes: 9000,
        )
        ..complete();

      expect(t.store.find(rec.id)!.messages!.items.single.totalBytes, 9000);
    });

    test('stop at the latest thousand, and still count all of them', () {
      final t = make();
      final rec = begin(t.engine);

      for (var i = 0; i < 1200; i++) {
        rec.message(
          sent: i.isEven,
          kind: FlutwireMessageKind.text,
          payload: utf('$i'),
        );
      }
      rec.complete();

      final messages = t.store.find(rec.id)!.messages!;
      expect(messages.items, hasLength(1000));
      expect(messages.total, 1200);
      expect(messages.dropped, 200);
      expect(messages.items.first.index, 200);
      expect(messages.items.last.index, 1199);
    });

    test('stop at a megabyte of payload, keeping the latest', () {
      final t = make(const FlutwireConfig(enabled: true, maxBodyBytes: 500000));
      final rec = begin(t.engine);

      for (var i = 0; i < 5; i++) {
        rec.message(
          sent: false,
          kind: FlutwireMessageKind.binary,
          payload: Uint8List(400000),
        );
      }
      rec.complete();

      final messages = t.store.find(rec.id)!.messages!;
      expect(messages.items.map((m) => m.index), [3, 4]);
      expect(messages.total, 5);
    });

    test('keep a single message that is bigger than the budget', () {
      final t = make(
        const FlutwireConfig(enabled: true, maxBodyBytes: 2000000),
      );
      final rec = begin(t.engine);

      rec
        ..message(
          sent: false,
          kind: FlutwireMessageKind.binary,
          payload: Uint8List(1500000),
        )
        ..complete();

      expect(t.store.find(rec.id)!.messages!.items, hasLength(1));
    });

    test('hide the fields the redaction names, in text and not in bytes', () {
      final t = make(
        const FlutwireConfig(
          enabled: true,
          redaction: FlutwireRedaction(bodyFields: {'password'}),
        ),
      );
      final rec = begin(t.engine);

      rec
        ..message(
          sent: true,
          kind: FlutwireMessageKind.text,
          payload: utf('{"user":"vega","password":"hunter2"}'),
        )
        ..message(
          sent: true,
          kind: FlutwireMessageKind.binary,
          payload: utf('{"password":"hunter2"}'),
        )
        ..complete();

      final [text, binary] = t.store.find(rec.id)!.messages!.items;
      expect(text.text, '{"user":"vega","password":"[redacted]"}');
      expect(utf8.decode(binary.bytes), '{"password":"hunter2"}');
    });

    test('are ignored once the call is over', () {
      final t = make();
      final rec = begin(t.engine);

      rec
        ..message(sent: true, kind: FlutwireMessageKind.text, payload: utf('a'))
        ..complete()
        ..message(
          sent: true,
          kind: FlutwireMessageKind.text,
          payload: utf('b'),
        );

      expect(t.store.find(rec.id)!.messages!.items, hasLength(1));
    });

    test('reach the store while the call runs, a burst at a time', () async {
      final t = make();
      final rec = begin(t.engine);

      for (var i = 0; i < 5; i++) {
        rec.message(
          sent: false,
          kind: FlutwireMessageKind.text,
          payload: utf('$i'),
        );
      }
      // The first one went out at once; the rest wait for the burst to end.
      expect(t.store.find(rec.id)!.messages!.items, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(t.store.find(rec.id)!.messages!.items, hasLength(5));
      expect(t.store.find(rec.id)!.isPending, isTrue);
    });
  });

  group('a server-sent event stream', () {
    FlutwireCallRecorder stream(FlutwireEngine engine, {String? type}) {
      final rec = begin(engine);
      rec.responseHead(
        statusCode: 200,
        headers: headers(type ?? 'text/event-stream; charset=utf-8'),
      );
      return rec;
    }

    test('lists its events as they complete', () {
      final t = make();
      final rec = stream(t.engine);

      rec
        ..responseBody(utf('event: tick\ndata: {"n":1}\n\n'))
        ..responseBody(utf('id: 9\ndata: second'))
        ..responseBody(utf(' half\n\n'))
        ..complete();

      final messages = t.store.find(rec.id)!.messages!;
      expect(messages.kind, FlutwireConversationKind.eventStream);
      final [first, second] = messages.items;
      expect(first.kind, FlutwireMessageKind.event);
      expect(first.sent, isFalse);
      expect(first.event, 'tick');
      expect(first.text, '{"n":1}');
      expect(second.eventId, '9');
      expect(second.text, 'second half');
    });

    test('still keeps the raw stream as the body of the response', () {
      final t = make();
      final rec = stream(t.engine);

      rec
        ..responseBody(utf('data: a\n\n'))
        ..complete();

      final call = t.store.find(rec.id)!;
      expect(call.response!.body.text, 'data: a\n\n');
    });

    test('is a pending call until it ends, with the events so far', () {
      final t = make();
      final rec = stream(t.engine);

      rec.responseBody(utf('data: a\n\n'));

      final call = t.store.find(rec.id)!;
      expect(call.isPending, isTrue);
      expect(call.messages!.items.single.text, 'a');
    });

    test('does not turn another response into events', () {
      final t = make();
      final rec = stream(t.engine, type: 'text/plain');

      rec
        ..responseBody(utf('data: a\n\n'))
        ..complete();

      expect(t.store.find(rec.id)!.messages, isNull);
    });

    test('drops an event the stream ended in the middle of', () {
      final t = make();
      final rec = stream(t.engine);

      rec
        ..responseBody(utf('data: whole\n\ndata: cut'))
        ..complete();

      expect(t.store.find(rec.id)!.messages!.items.map((m) => m.text), [
        'whole',
      ]);
    });

    test('keeps the size of an event that was cut', () {
      final t = make(const FlutwireConfig(enabled: true, maxBodyBytes: 8));
      final rec = stream(t.engine);

      rec
        ..responseBody(utf('data: ${'z' * 50}\n\n'))
        ..complete();

      final message = t.store.find(rec.id)!.messages!.items.single;
      expect(message.bytes, hasLength(8));
      expect(message.totalBytes, 50);
    });
  });
}
