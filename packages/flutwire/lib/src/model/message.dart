import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What a message of a conversation is.
enum FlutwireMessageKind {
  /// A WebSocket text message.
  text,

  /// A WebSocket binary message.
  binary,

  /// A WebSocket ping, which asks the other side to answer with a pong.
  ping,

  /// A WebSocket pong.
  pong,

  /// A WebSocket close frame, which carries a status code and a reason.
  close,

  /// A server-sent event.
  event,
}

/// What kind of conversation a call carries after its response head.
enum FlutwireConversationKind {
  /// A WebSocket: messages go both ways until one side closes.
  webSocket,

  /// A server-sent event stream: events arrive until the server ends it.
  eventStream,
}

/// One message of a WebSocket conversation, or one server-sent event.
///
/// Like a body, a message keeps only the first bytes of its payload. [totalBytes]
/// is the real size, so a reader can tell a message that was cut from one that
/// is whole.
@immutable
final class FlutwireMessage {
  /// Creates a message. [totalBytes] is the size of the whole payload, which
  /// is more than the length of [bytes] when some of it was not kept.
  const FlutwireMessage({
    required this.index,
    required this.sent,
    required this.at,
    required this.kind,
    required this.bytes,
    required this.totalBytes,
    this.event,
    this.eventId,
    this.undecoded = false,
  });

  /// Restores a message written by [toJson].
  factory FlutwireMessage.fromJson(Map<String, Object?> json) {
    final data = json['data'] as String?;
    final bytes = data == null ? Uint8List(0) : base64Decode(data);
    return FlutwireMessage(
      index: (json['index'] as num?)?.toInt() ?? 0,
      sent: json['sent'] as bool? ?? false,
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      kind: FlutwireMessageKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => FlutwireMessageKind.binary,
      ),
      bytes: bytes,
      totalBytes: (json['total'] as num?)?.toInt() ?? bytes.length,
      event: json['event'] as String?,
      eventId: json['id'] as String?,
      undecoded: json['undecoded'] as bool? ?? false,
    );
  }

  /// The position in the conversation, counting from 0. Messages that were not
  /// kept leave a gap.
  final int index;

  /// Whether the app sent it. False for what the server sent.
  final bool sent;

  /// When the message was complete.
  final DateTime at;

  /// What the message is.
  final FlutwireMessageKind kind;

  /// The first bytes of the payload, as far as they were kept. A compressed
  /// message is kept after decompression.
  final Uint8List bytes;

  /// The size of the whole payload in bytes.
  final int totalBytes;

  /// The `event:` field of a server-sent event, when it had one.
  final String? event;

  /// The `id:` field of a server-sent event, when it had one.
  final String? eventId;

  /// Whether the message was compressed and could not be decompressed, so
  /// [bytes] are the compressed ones.
  final bool undecoded;

  /// Whether some of the payload was not kept.
  bool get truncated => totalBytes > bytes.length;

  /// The payload as text, for the kinds that carry text, or null.
  String? get text => switch (kind) {
    FlutwireMessageKind.text ||
    FlutwireMessageKind.event => utf8.decode(bytes, allowMalformed: true),
    FlutwireMessageKind.close => closeReason,
    _ => null,
  };

  /// The status code of a close frame, or null when there is none.
  int? get closeCode => kind == FlutwireMessageKind.close && bytes.length >= 2
      ? (bytes[0] << 8) | bytes[1]
      : null;

  /// The reason of a close frame, which is empty when there is none.
  String? get closeReason => kind == FlutwireMessageKind.close
      ? utf8.decode(
          bytes.length > 2 ? bytes.sublist(2) : Uint8List(0),
          allowMalformed: true,
        )
      : null;

  static final RegExp _whitespace = RegExp(r'\s+');

  /// What the message holds in a line or two, for a list or a text export: the
  /// text of a text message or an event, the code and the reason of a close,
  /// and the first bytes, in hex, of anything else.
  String get preview {
    switch (kind) {
      case FlutwireMessageKind.text:
      case FlutwireMessageKind.event:
        final flat = (text ?? '').replaceAll(_whitespace, ' ').trim();
        return flat.length <= 240 ? flat : '${flat.substring(0, 240)}…';
      case FlutwireMessageKind.close:
        final code = closeCode;
        final reason = closeReason ?? '';
        return [
          if (code != null) '$code',
          if (reason.isNotEmpty) reason,
        ].join(' ');
      case FlutwireMessageKind.binary:
      case FlutwireMessageKind.ping:
      case FlutwireMessageKind.pong:
        if (bytes.isEmpty) return '';
        final shown = bytes.length <= 16 ? bytes : bytes.sublist(0, 16);
        final hex = [
          for (final byte in shown) byte.toRadixString(16).padLeft(2, '0'),
        ].join(' ');
        return totalBytes > shown.length ? '$hex …' : hex;
    }
  }

  /// A JSON-encodable form, with the payload in base64.
  Map<String, Object?> toJson() => {
    'index': index,
    'sent': sent,
    'at': at.toIso8601String(),
    'kind': kind.name,
    if (bytes.isNotEmpty) 'data': base64Encode(bytes),
    'total': totalBytes,
    if (event != null) 'event': event,
    if (eventId != null) 'id': eventId,
    if (undecoded) 'undecoded': true,
  };
}

/// The messages of a call, as far as they were kept.
///
/// A conversation can run for hours, so only the latest messages are kept, and
/// [total] says how many there were.
@immutable
final class FlutwireMessages {
  /// Creates the messages of a conversation. [keptBytes] is the size of the
  /// payloads in [items].
  const FlutwireMessages({
    required this.kind,
    required this.items,
    required this.total,
    required this.keptBytes,
  }) : loaded = true;

  /// Messages whose payloads live on disk and have not been read yet. It keeps
  /// the count and the size, so a list row can still describe them.
  const FlutwireMessages.unloaded({
    required this.kind,
    required this.total,
    required this.keptBytes,
  }) : items = const [],
       loaded = false;

  /// Restores the description written by [toJson], without the messages.
  factory FlutwireMessages.fromJson(Map<String, Object?> json) =>
      FlutwireMessages.unloaded(
        kind: FlutwireConversationKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => FlutwireConversationKind.webSocket,
        ),
        total: (json['total'] as num?)?.toInt() ?? 0,
        keptBytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );

  /// Whether this is a WebSocket or an event stream.
  final FlutwireConversationKind kind;

  /// The messages kept, oldest first.
  final List<FlutwireMessage> items;

  /// How many messages there were, kept or not.
  final int total;

  /// How many payload bytes were kept, whether or not they are loaded now.
  final int keptBytes;

  /// Whether [items] holds the messages. A summary read from disk does not,
  /// until the full call is loaded.
  final bool loaded;

  /// How many payload bytes are held in memory now.
  int get memoryBytes => loaded ? keptBytes : 0;

  /// How many messages were not kept.
  int get dropped => loaded ? total - items.length : 0;

  /// A copy that carries [items] in place of the placeholder.
  FlutwireMessages withItems(List<FlutwireMessage> items) => FlutwireMessages(
    kind: kind,
    items: items,
    total: total,
    keptBytes: items.fold(0, (sum, m) => sum + m.bytes.length),
  );

  /// A copy that keeps the count and lets go of the messages.
  FlutwireMessages unload() =>
      FlutwireMessages.unloaded(kind: kind, total: total, keptBytes: keptBytes);

  /// A description without the payloads, for the summary kept on disk.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'total': total,
    'bytes': keptBytes,
  };
}
