import 'dart:collection';

import '../../model/message.dart';

/// The messages of one call, kept within bounds.
///
/// A conversation can run for hours, so the log keeps the latest messages and
/// lets go of the oldest, and it counts all of them.
final class MessageLog {
  /// Creates a log that keeps at most [maxMessages] messages, and at most
  /// [maxBytes] of payload between them.
  MessageLog({this.maxMessages = 1000, this.maxBytes = 1 << 20});

  /// The most messages the log keeps.
  final int maxMessages;

  /// The most payload bytes the messages of the log keep together. A single
  /// message that is bigger than that is kept all the same, on its own.
  final int maxBytes;

  final Queue<FlutwireMessage> _items = Queue<FlutwireMessage>();
  int _total = 0;
  int _bytes = 0;

  /// How many messages were added, kept or not. It is also the index the next
  /// one gets.
  int get total => _total;

  /// Adds [message] and lets go of the oldest ones while the log is over a
  /// limit.
  void add(FlutwireMessage message) {
    _items.add(message);
    _total++;
    _bytes += message.bytes.length;
    while (_items.length > maxMessages ||
        (_bytes > maxBytes && _items.length > 1)) {
      _bytes -= _items.removeFirst().bytes.length;
    }
  }

  /// What the log holds now, as the messages of a call of the given [kind].
  FlutwireMessages snapshot(FlutwireConversationKind kind) => FlutwireMessages(
    kind: kind,
    items: List.unmodifiable(_items),
    total: _total,
    keptBytes: _bytes,
  );
}
