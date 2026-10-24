import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

FlutwireMessage message(
  FlutwireMessageKind kind,
  List<int> bytes, {
  int? total,
  String? event,
  String? eventId,
  bool undecoded = false,
}) => FlutwireMessage(
  index: 3,
  sent: true,
  at: DateTime.utc(2026, 10, 24, 12, 0, 1),
  kind: kind,
  bytes: Uint8List.fromList(bytes),
  totalBytes: total ?? bytes.length,
  event: event,
  eventId: eventId,
  undecoded: undecoded,
);

void main() {
  group('a message', () {
    test('reads text as text and nothing else', () {
      final text = message(FlutwireMessageKind.text, utf8.encode('héllo'));
      final event = message(FlutwireMessageKind.event, utf8.encode('{"a":1}'));
      final binary = message(FlutwireMessageKind.binary, [1, 2]);
      final ping = message(FlutwireMessageKind.ping, [1]);

      expect(text.text, 'héllo');
      expect(event.text, '{"a":1}');
      expect(binary.text, isNull);
      expect(ping.text, isNull);
    });

    test('reads the code and the reason out of a close', () {
      final close = message(FlutwireMessageKind.close, [
        0x03,
        0xe8,
        ...utf8.encode('bye'),
      ]);

      expect(close.closeCode, 1000);
      expect(close.closeReason, 'bye');
      expect(close.text, 'bye');
    });

    test('has no code in a close with no payload', () {
      final close = message(FlutwireMessageKind.close, const []);

      expect(close.closeCode, isNull);
      expect(close.closeReason, '');
    });

    test('has no code unless it is a close', () {
      expect(message(FlutwireMessageKind.text, [3, 232]).closeCode, isNull);
    });

    test('is cut when its payload is shorter than the whole', () {
      expect(
        message(FlutwireMessageKind.text, [65], total: 9).truncated,
        isTrue,
      );
      expect(message(FlutwireMessageKind.text, [65]).truncated, isFalse);
    });

    test('survives a trip through JSON with everything it had', () {
      final original = message(
        FlutwireMessageKind.event,
        utf8.encode('payload'),
        total: 700,
        event: 'tick',
        eventId: '12',
        undecoded: true,
      );

      final back = FlutwireMessage.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(back.index, 3);
      expect(back.sent, isTrue);
      expect(back.at, original.at);
      expect(back.kind, FlutwireMessageKind.event);
      expect(back.bytes, original.bytes);
      expect(back.totalBytes, 700);
      expect(back.event, 'tick');
      expect(back.eventId, '12');
      expect(back.undecoded, isTrue);
    });

    test('leaves out of its JSON what it does not have', () {
      final json = message(FlutwireMessageKind.ping, const []).toJson();

      expect(json.containsKey('data'), isFalse);
      expect(json.containsKey('event'), isFalse);
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('undecoded'), isFalse);
    });

    test('is read back from a line that lost its optional parts', () {
      final back = FlutwireMessage.fromJson({
        'index': 1,
        'sent': false,
        'at': '2026-10-24T12:00:00.000Z',
        'kind': 'unheard-of',
      });

      expect(back.kind, FlutwireMessageKind.binary);
      expect(back.bytes, isEmpty);
      expect(back.totalBytes, 0);
    });
  });

  group('the preview of a message', () {
    test('is the text on one line', () {
      final text = message(
        FlutwireMessageKind.text,
        utf8.encode('line one\n\n   line   two'),
      );

      expect(text.preview, 'line one line two');
    });

    test('is cut where a long text gets unwieldy', () {
      final text = message(FlutwireMessageKind.text, utf8.encode('x' * 500));

      expect(text.preview, hasLength(241));
      expect(text.preview, endsWith('…'));
    });

    test('is the code and the reason of a close', () {
      final close = message(FlutwireMessageKind.close, [
        0x03,
        0xe9,
        ...utf8.encode('going away'),
      ]);

      expect(close.preview, '1001 going away');
    });

    test('is the first bytes of anything else, in hex', () {
      expect(
        message(FlutwireMessageKind.binary, [0, 255, 16]).preview,
        '00 ff 10',
      );
      expect(message(FlutwireMessageKind.pong, const []).preview, '');
    });

    test('says there is more when the bytes go on', () {
      final binary = message(
        FlutwireMessageKind.binary,
        List.generate(40, (i) => i),
        total: 40,
      );

      expect(binary.preview, endsWith('0f …'));
      expect(
        binary.preview.split(' ').where((p) => p.length == 2),
        hasLength(16),
      );
    });
  });

  group('the messages of a call', () {
    FlutwireMessages loaded() => FlutwireMessages(
      kind: FlutwireConversationKind.webSocket,
      items: [
        message(FlutwireMessageKind.text, [65, 66]),
        message(FlutwireMessageKind.text, [67]),
      ],
      total: 5,
      keptBytes: 3,
    );

    test('count what was kept and what was not', () {
      final messages = loaded();

      expect(messages.dropped, 3);
      expect(messages.memoryBytes, 3);
    });

    test('let go of the messages and keep the count and the size', () {
      final unloaded = loaded().unload();

      expect(unloaded.loaded, isFalse);
      expect(unloaded.items, isEmpty);
      expect(unloaded.total, 5);
      expect(unloaded.keptBytes, 3);
      expect(unloaded.memoryBytes, 0);
      expect(unloaded.dropped, 0);
    });

    test('take the messages back and count their size again', () {
      final back = loaded().unload().withItems([
        message(FlutwireMessageKind.text, [1, 2, 3, 4]),
      ]);

      expect(back.loaded, isTrue);
      expect(back.keptBytes, 4);
      expect(back.total, 5);
    });

    test('write only a description in the summary of a call', () {
      final json = loaded().toJson();

      expect(json, {'kind': 'webSocket', 'total': 5, 'bytes': 3});
      final back = FlutwireMessages.fromJson(json);
      expect(back.loaded, isFalse);
      expect(back.kind, FlutwireConversationKind.webSocket);
      expect(back.total, 5);
      expect(back.keptBytes, 3);
    });
  });
}
