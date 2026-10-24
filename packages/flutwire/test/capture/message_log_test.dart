import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/capture/messages/message_log.dart';

FlutwireMessage message(int index, {int bytes = 1}) => FlutwireMessage(
  index: index,
  sent: false,
  at: DateTime.utc(2026, 10, 24),
  kind: FlutwireMessageKind.binary,
  bytes: Uint8List(bytes),
  totalBytes: bytes,
);

void main() {
  test('keeps every message while it is within its limits', () {
    final log = MessageLog();
    for (var i = 0; i < 5; i++) {
      log.add(message(i));
    }

    final snapshot = log.snapshot(FlutwireConversationKind.webSocket);
    expect(snapshot.items.map((m) => m.index), [0, 1, 2, 3, 4]);
    expect(snapshot.total, 5);
    expect(snapshot.keptBytes, 5);
    expect(snapshot.kind, FlutwireConversationKind.webSocket);
  });

  test('counts a message by the index the next one gets', () {
    final log = MessageLog();

    expect(log.total, 0);

    log
      ..add(message(0))
      ..add(message(1));

    expect(log.total, 2);
  });

  test('lets go of the oldest messages past the count limit', () {
    final log = MessageLog(maxMessages: 3);
    for (var i = 0; i < 10; i++) {
      log.add(message(i));
    }

    final snapshot = log.snapshot(FlutwireConversationKind.webSocket);
    expect(snapshot.items.map((m) => m.index), [7, 8, 9]);
    expect(snapshot.total, 10);
    expect(snapshot.dropped, 7);
    expect(snapshot.keptBytes, 3);
  });

  test('lets go of the oldest messages past the byte limit', () {
    final log = MessageLog(maxBytes: 100);
    for (var i = 0; i < 5; i++) {
      log.add(message(i, bytes: 40));
    }

    final snapshot = log.snapshot(FlutwireConversationKind.webSocket);
    expect(snapshot.items.map((m) => m.index), [3, 4]);
    expect(snapshot.keptBytes, 80);
  });

  test('keeps a single message that is bigger than the byte limit', () {
    final log = MessageLog(maxBytes: 10)..add(message(0, bytes: 500));

    expect(
      log.snapshot(FlutwireConversationKind.webSocket).items,
      hasLength(1),
    );
  });

  test('replaces a big message with the next one, which is bigger still', () {
    final log = MessageLog(maxBytes: 10)
      ..add(message(0, bytes: 500))
      ..add(message(1, bytes: 600));

    final snapshot = log.snapshot(FlutwireConversationKind.webSocket);
    expect(snapshot.items.map((m) => m.index), [1]);
    expect(snapshot.keptBytes, 600);
  });

  test('hands out a snapshot that later messages do not change', () {
    final log = MessageLog()..add(message(0));
    final snapshot = log.snapshot(FlutwireConversationKind.webSocket);

    log.add(message(1));

    expect(snapshot.items, hasLength(1));
    expect(() => snapshot.items.add(message(2)), throwsUnsupportedError);
  });
}
