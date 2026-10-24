import 'dart:io';
import 'dart:typed_data';

import '../../model/message.dart';

/// What the WebSocket handshake agreed about compression, which decides how the
/// messages of each direction are read.
final class WebSocketDeflate {
  /// Creates the agreement.
  const WebSocketDeflate({
    this.serverNoContextTakeover = false,
    this.clientNoContextTakeover = false,
  });

  /// Reads the `Sec-WebSocket-Extensions` header of the handshake response.
  /// Returns null when `permessage-deflate` was not agreed.
  static WebSocketDeflate? parse(String? header) {
    if (header == null) return null;
    for (final extension in header.split(',')) {
      final parts = extension.split(';').map((p) => p.trim().toLowerCase());
      if (parts.isEmpty || parts.first != 'permessage-deflate') continue;
      final parameters = parts.skip(1).toSet();
      return WebSocketDeflate(
        serverNoContextTakeover: parameters.contains(
          'server_no_context_takeover',
        ),
        clientNoContextTakeover: parameters.contains(
          'client_no_context_takeover',
        ),
      );
    }
    return null;
  }

  /// Whether the server starts a fresh compression window for every message.
  final bool serverNoContextTakeover;

  /// Whether the client starts a fresh compression window for every message.
  final bool clientNoContextTakeover;
}

/// Reads the frames one side of a WebSocket connection wrote, from the bytes
/// as they cross the socket, and reports each message once it is complete.
///
/// A message that arrives in several frames is joined, a compressed one is
/// decompressed, and the ping, pong and close frames in between are reported
/// as messages of their own. Only the first [maxBytes] of a payload are kept,
/// and the size of the whole is reported.
///
/// Anything it cannot make sense of stops it for good: it never throws, and a
/// connection it cannot read is simply not listed.
final class WebSocketReader {
  /// Creates a reader that calls [onMessage] for each message.
  ///
  /// [deflate] says whether `permessage-deflate` was agreed, and
  /// [noContextTakeover] whether this side starts a fresh window for every
  /// message.
  WebSocketReader({
    required this.onMessage,
    this.maxBytes = 1 << 20,
    this.deflate = false,
    this.noContextTakeover = false,
  });

  /// Called with each complete message.
  final void Function(
    FlutwireMessageKind kind,
    Uint8List payload,
    int totalBytes, {
    required bool undecoded,
  })
  onMessage;

  /// How many bytes of a payload are kept.
  final int maxBytes;

  /// Whether the messages may be compressed.
  final bool deflate;

  /// Whether every compressed message stands alone.
  final bool noContextTakeover;

  /// Whether the bytes stopped making sense, after which nothing is reported.
  bool get broken => _broken;

  static const List<int> _tail = [0x00, 0x00, 0xff, 0xff];

  final BytesBuilder _head = BytesBuilder(copy: false);
  final Uint8List _mask = Uint8List(4);
  final BytesBuilder _kept = BytesBuilder(copy: false);
  final BytesBuilder _control = BytesBuilder(copy: false);
  bool _broken = false;
  int _headNeeded = 2;
  bool _inPayload = false;
  bool _fin = false;
  bool _masked = false;
  int _opcode = 0;
  int _remaining = 0;
  int _maskOffset = 0;
  FlutwireMessageKind? _kind;
  bool _compressed = false;
  bool _undecoded = false;
  int _total = 0;
  RawZLibFilter? _inflater;
  bool _inflateBroken = false;

  /// Feeds the next [chunk] of bytes of this side of the connection.
  void add(List<int> chunk) {
    if (_broken) return;
    try {
      _read(chunk);
    } on Object {
      _broken = true;
    }
  }

  void _read(List<int> chunk) {
    var at = 0;
    while (at < chunk.length && !_broken) {
      if (!_inPayload) {
        _head.addByte(chunk[at++]);
        if (_head.length == 2) _headNeeded = _lengthOfHead(_head.toBytes());
        if (_head.length >= _headNeeded) _startFrame(_head.takeBytes());
        continue;
      }
      final take = chunk.length - at < _remaining
          ? chunk.length - at
          : _remaining;
      final bytes = Uint8List(take);
      for (var i = 0; i < take; i++) {
        final byte = chunk[at + i];
        bytes[i] = _masked ? byte ^ _mask[(_maskOffset + i) & 3] : byte;
      }
      _maskOffset += take;
      at += take;
      _remaining -= take;
      _payload(bytes);
      if (_remaining == 0) _endFrame();
    }
  }

  /// How many bytes the header of a frame takes, from its first two.
  static int _lengthOfHead(Uint8List first) {
    final length = first[1] & 0x7f;
    final extended = length == 126 ? 2 : (length == 127 ? 8 : 0);
    final mask = (first[1] & 0x80) != 0 ? 4 : 0;
    return 2 + extended + mask;
  }

  void _startFrame(Uint8List head) {
    _headNeeded = 2;
    _fin = (head[0] & 0x80) != 0;
    final rsv1 = (head[0] & 0x40) != 0;
    final reserved = (head[0] & 0x30) != 0;
    _opcode = head[0] & 0x0f;
    _masked = (head[1] & 0x80) != 0;
    var length = head[1] & 0x7f;
    var at = 2;
    if (length == 126) {
      length = (head[2] << 8) | head[3];
      at = 4;
    } else if (length == 127) {
      length = 0;
      for (var i = 0; i < 8; i++) {
        length = (length << 8) | head[2 + i];
      }
      at = 10;
    }
    if (_masked) {
      for (var i = 0; i < 4; i++) {
        _mask[i] = head[at + i];
      }
    }
    _maskOffset = 0;
    final control = _opcode >= 8;
    final invalid =
        length < 0 ||
        reserved ||
        (rsv1 && (!deflate || control || _opcode == 0)) ||
        (control && (!_fin || length > 125)) ||
        (_opcode > 2 && !control) ||
        (_opcode > 10) ||
        (_opcode == 0 && _kind == null) ||
        ((_opcode == 1 || _opcode == 2) && _kind != null);
    if (invalid) {
      _broken = true;
      return;
    }
    if (_opcode == 1 || _opcode == 2) {
      _kind = _opcode == 1
          ? FlutwireMessageKind.text
          : FlutwireMessageKind.binary;
      _compressed = rsv1;
      _undecoded = false;
      _total = 0;
      _kept.clear();
    }
    _remaining = length;
    _inPayload = true;
    if (_remaining == 0) _endFrame();
  }

  void _payload(Uint8List bytes) {
    if (_opcode >= 8) {
      _control.add(bytes);
    } else if (_compressed) {
      _inflate(bytes);
    } else {
      _total += bytes.length;
      _keep(bytes);
    }
  }

  void _endFrame() {
    _inPayload = false;
    if (_opcode >= 8) {
      final payload = _control.takeBytes();
      final kind = switch (_opcode) {
        8 => FlutwireMessageKind.close,
        9 => FlutwireMessageKind.ping,
        _ => FlutwireMessageKind.pong,
      };
      onMessage(kind, payload, payload.length, undecoded: false);
      return;
    }
    if (!_fin) return;
    if (_compressed) {
      _inflate(_tail, tail: true);
      if (noContextTakeover) _inflater = null;
    }
    final kind = _kind!;
    final payload = _kept.takeBytes();
    final total = _total;
    final undecoded = _undecoded;
    _kind = null;
    _compressed = false;
    _total = 0;
    onMessage(kind, payload, total, undecoded: undecoded);
  }

  void _keep(List<int> bytes) {
    final room = maxBytes - _kept.length;
    if (room <= 0) return;
    _kept.add(bytes.length <= room ? bytes : bytes.sublist(0, room));
  }

  void _inflate(List<int> data, {bool tail = false}) {
    if (_inflateBroken) {
      // The window is lost, so what follows cannot be read. The bytes are kept
      // as they came, and the message says they are not decoded.
      _undecoded = true;
      if (!tail) {
        _total += data.length;
        _keep(data);
      }
      return;
    }
    try {
      final filter = _inflater ??= RawZLibFilter.inflateFilter(raw: true);
      filter.process(data, 0, data.length);
      while (true) {
        final out = filter.processed();
        if (out == null || out.isEmpty) break;
        _total += out.length;
        _keep(out);
      }
    } on Object {
      _inflateBroken = true;
      _inflater = null;
      _undecoded = true;
    }
  }
}
