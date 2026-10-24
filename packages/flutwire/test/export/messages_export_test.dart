import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/export/har.dart';
import 'package:flutwire/src/export/text.dart';

final started = DateTime.utc(2026, 10, 24, 12);

FlutwireMessage message(
  int index,
  FlutwireMessageKind kind,
  List<int> bytes, {
  bool sent = false,
  int millis = 0,
  String? event,
  String? eventId,
}) => FlutwireMessage(
  index: index,
  sent: sent,
  at: started.add(Duration(milliseconds: millis)),
  kind: kind,
  bytes: Uint8List.fromList(bytes),
  totalBytes: bytes.length,
  event: event,
  eventId: eventId,
);

FlutwireCall conversation(
  List<FlutwireMessage> items, {
  FlutwireConversationKind kind = FlutwireConversationKind.webSocket,
  int? total,
  bool loaded = true,
}) {
  final messages = FlutwireMessages(
    kind: kind,
    items: items,
    total: total ?? items.length,
    keptBytes: items.fold(0, (sum, m) => sum + m.bytes.length),
  );
  return FlutwireCall(
    id: 1,
    method: 'GET',
    uri: Uri.parse('wss://api.test/live'),
    source: FlutwireSource.io,
    state: FlutwireCallState.completed,
    startedAt: started,
    endedAt: started.add(const Duration(seconds: 2)),
    request: FlutwireRequest(
      headers: FlutwireHeaders.empty,
      body: FlutwireBody.empty(),
    ),
    response: FlutwireResponse(
      statusCode: 101,
      headers: FlutwireHeaders.fromMap({'upgrade': 'websocket'}),
      body: FlutwireBody.empty(),
    ),
    messages: loaded ? messages : messages.unload(),
  );
}

List<Object?> har(FlutwireCall call, String key) {
  final entries =
      (toHar([call])['log']! as Map<String, Object?>)['entries']!
          as List<Object?>;
  return (entries.single! as Map<String, Object?>)[key] as List<Object?>;
}

void main() {
  group('HAR', () {
    test('lists the messages of a WebSocket the way Chrome does', () {
      final call = conversation([
        message(0, FlutwireMessageKind.text, utf8.encode('hello'), sent: true),
        message(1, FlutwireMessageKind.binary, [1, 2, 3], millis: 500),
        message(2, FlutwireMessageKind.ping, const [], millis: 900),
        message(3, FlutwireMessageKind.pong, const [], sent: true, millis: 950),
        message(4, FlutwireMessageKind.close, [0x03, 0xe8], millis: 1500),
      ]);

      final frames = har(
        call,
        '_webSocketMessages',
      ).cast<Map<String, Object?>>();

      expect(frames.map((f) => f['type']), [
        'send',
        'receive',
        'receive',
        'send',
        'receive',
      ]);
      expect(frames.map((f) => f['opcode']), [1, 2, 9, 10, 8]);
      expect(frames.first['data'], 'hello');
      expect(frames[1]['data'], base64Encode([1, 2, 3]));
      expect(frames.first['time'], started.microsecondsSinceEpoch / 1000000);
      expect(
        (frames[1]['time']! as double) - (frames.first['time']! as double),
        closeTo(0.5, 1e-9),
      );
    });

    test('marks the entry as a WebSocket', () {
      final call = conversation([
        message(0, FlutwireMessageKind.text, [65]),
      ]);

      final entry =
          ((toHar([call])['log']! as Map<String, Object?>)['entries']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;

      expect(entry['_resourceType'], 'websocket');
    });

    test('lists the events of a stream with their names and ids', () {
      final call = conversation([
        message(
          0,
          FlutwireMessageKind.event,
          utf8.encode('{"n":1}'),
          event: 'tick',
          eventId: '7',
        ),
        message(1, FlutwireMessageKind.event, utf8.encode('plain'), millis: 20),
      ], kind: FlutwireConversationKind.eventStream);

      final events = har(
        call,
        '_eventSourceMessages',
      ).cast<Map<String, Object?>>();

      expect(events.map((e) => e['eventName']), ['tick', 'message']);
      expect(events.first['eventId'], '7');
      expect(events.last.containsKey('eventId'), isFalse);
      expect(events.map((e) => e['data']), ['{"n":1}', 'plain']);
    });

    test('leaves messages out when they were not read back from disk', () {
      final call = conversation([
        message(0, FlutwireMessageKind.text, [65]),
      ], loaded: false);

      final entry =
          ((toHar([call])['log']! as Map<String, Object?>)['entries']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;

      expect(entry.containsKey('_webSocketMessages'), isFalse);
    });

    test('writes an ordinary call as before', () {
      final call = conversation([]).copyWith();
      final plain = FlutwireCall(
        id: 2,
        method: 'GET',
        uri: Uri.parse('https://api.test/'),
        source: FlutwireSource.io,
        startedAt: started,
        request: call.request,
      );

      final entry =
          ((toHar([plain])['log']! as Map<String, Object?>)['entries']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;

      expect(entry.containsKey('_webSocketMessages'), isFalse);
      expect(entry.containsKey('_resourceType'), isFalse);
    });
  });

  group('text', () {
    test('counts the messages and lists them with their direction', () {
      final text = callToText(
        conversation([
          message(
            0,
            FlutwireMessageKind.text,
            utf8.encode('hello'),
            sent: true,
          ),
          message(
            1,
            FlutwireMessageKind.text,
            utf8.encode('world'),
            millis: 1250,
          ),
          message(2, FlutwireMessageKind.close, [
            0x03,
            0xe8,
            ...utf8.encode('done'),
          ], millis: 1900),
        ]),
      );

      expect(text, contains('Messages:     3'));
      expect(text, contains('--- Messages ---'));
      expect(text, contains('-> +0 ms'));
      expect(text, contains('hello'));
      expect(text, contains('<- +1.25 s'));
      expect(text, contains('1000 done'));
    });

    test('says how many were kept when the first ones were not', () {
      final text = callToText(
        conversation([
          message(200, FlutwireMessageKind.text, [65]),
        ], total: 201),
      );

      expect(text, contains('Messages:     201 (1 kept)'));
    });

    test('calls the events of a stream events', () {
      final text = callToText(
        conversation([
          message(
            0,
            FlutwireMessageKind.event,
            utf8.encode('a'),
            event: 'tick',
          ),
        ], kind: FlutwireConversationKind.eventStream),
      );

      expect(text, contains('Events:       1'));
      expect(text, contains('--- Events ---'));
      expect(text, contains('tick'));
    });

    test('has no section for a call with no messages', () {
      final text = callToText(conversation([]));

      expect(text, isNot(contains('--- Messages ---')));
      expect(text, contains('Messages:     0'));
    });
  });
}
