import 'dart:convert';
import 'dart:typed_data';

import '../config.dart';
import '../model/body.dart';
import '../model/call.dart';
import 'decoded_text.dart';

/// Shows a MessagePack body as indented text that reads like JSON.
///
/// MessagePack describes itself, so it needs no schema. The decoder answers for
/// bodies whose media type says MessagePack (`application/msgpack`,
/// `application/x-msgpack`, `application/vnd.msgpack` or a `+msgpack` suffix)
/// and passes on anything it cannot read to the end, or that was cut. Inspector
/// builds register it for you.
///
/// What JSON cannot say is written as text: bytes are hex, a map with keys that
/// are not strings has them written as text, an extension is its type number
/// and its bytes, and a timestamp is an ISO 8601 date.
final class FlutwireMessagePackDecoder implements FlutwireBodyDecoder {
  /// Creates the decoder.
  const FlutwireMessagePackDecoder();

  @override
  String get name => 'MessagePack';

  @override
  String? decode(
    FlutwireCall call,
    FlutwireBody body, {
    required bool isRequest,
  }) {
    if (!body.loaded || body.isEmpty || body.truncated) return null;
    if (!_isMessagePack(body.mimeType)) return null;
    try {
      final reader = _Reader(body.bytes);
      final values = <Object?>[];
      while (!reader.atEnd) {
        values.add(reader.read(0));
      }
      return renderDecoded(values.length == 1 ? values.single : values);
    } on FormatException {
      return null;
    }
  }

  static bool _isMessagePack(String? mime) =>
      mime == 'application/msgpack' ||
      mime == 'application/x-msgpack' ||
      mime == 'application/vnd.msgpack' ||
      (mime != null && mime.endsWith('+msgpack'));
}

/// How deep values may nest before the reader gives up.
const int _maxDepth = 64;

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  bool get atEnd => _at >= _bytes.length;

  Object? read(int depth) {
    if (depth > _maxDepth) throw const FormatException('nested too deep');
    final tag = _byte();
    if (tag <= 0x7f) return tag;
    if (tag >= 0xe0) return tag - 256;
    if (tag >= 0xa0 && tag <= 0xbf) return _string(tag & 0x1f);
    if (tag >= 0x90 && tag <= 0x9f) return _array(tag & 0x0f, depth);
    if (tag >= 0x80 && tag <= 0x8f) return _map(tag & 0x0f, depth);
    switch (tag) {
      case 0xc0:
        return null;
      case 0xc2:
        return false;
      case 0xc3:
        return true;
      case 0xc4:
        return _bytesOf(_unsigned(1));
      case 0xc5:
        return _bytesOf(_unsigned(2));
      case 0xc6:
        return _bytesOf(_unsigned(4));
      case 0xc7:
        return _extension(_unsigned(1));
      case 0xc8:
        return _extension(_unsigned(2));
      case 0xc9:
        return _extension(_unsigned(4));
      case 0xca:
        return _float(4);
      case 0xcb:
        return _float(8);
      case 0xcc:
        return _unsigned(1);
      case 0xcd:
        return _unsigned(2);
      case 0xce:
        return _unsigned(4);
      case 0xcf:
        return _wide(signed: false);
      case 0xd0:
        return _signed(1);
      case 0xd1:
        return _signed(2);
      case 0xd2:
        return _signed(4);
      case 0xd3:
        return _wide(signed: true);
      case 0xd4:
        return _extension(1);
      case 0xd5:
        return _extension(2);
      case 0xd6:
        return _extension(4);
      case 0xd7:
        return _extension(8);
      case 0xd8:
        return _extension(16);
      case 0xd9:
        return _string(_unsigned(1));
      case 0xda:
        return _string(_unsigned(2));
      case 0xdb:
        return _string(_unsigned(4));
      case 0xdc:
        return _array(_unsigned(2), depth);
      case 0xdd:
        return _array(_unsigned(4), depth);
      case 0xde:
        return _map(_unsigned(2), depth);
      case 0xdf:
        return _map(_unsigned(4), depth);
    }
    throw FormatException(
      '0x${tag.toRadixString(16)} is not a MessagePack tag',
    );
  }

  int _byte() {
    if (_at >= _bytes.length) throw const FormatException('cut short');
    return _bytes[_at++];
  }

  void _need(int count) {
    if (count < 0 || _at + count > _bytes.length) {
      throw const FormatException('cut short');
    }
  }

  int _unsigned(int size) {
    _need(size);
    final value = switch (size) {
      1 => _data.getUint8(_at),
      2 => _data.getUint16(_at),
      _ => _data.getUint32(_at),
    };
    _at += size;
    return value;
  }

  int _signed(int size) {
    _need(size);
    final value = switch (size) {
      1 => _data.getInt8(_at),
      2 => _data.getInt16(_at),
      _ => _data.getInt32(_at),
    };
    _at += size;
    return value;
  }

  /// A 64-bit integer: an `int` while it is safe to hold in one, a `BigInt`
  /// from there on, so the number is never rounded.
  Object _wide({required bool signed}) {
    _need(8);
    final high = signed ? _data.getInt32(_at) : _data.getUint32(_at);
    final low = _data.getUint32(_at + 4);
    _at += 8;
    if (high >= -0x200000 && high < 0x200000) return high * 0x100000000 + low;
    return (BigInt.from(high) << 32) + BigInt.from(low);
  }

  double _float(int size) {
    _need(size);
    final value = size == 4 ? _data.getFloat32(_at) : _data.getFloat64(_at);
    _at += size;
    return value;
  }

  String _string(int length) {
    _need(length);
    final text = utf8.decode(
      Uint8List.sublistView(_bytes, _at, _at + length),
      allowMalformed: true,
    );
    _at += length;
    return text;
  }

  DecodedBytes _bytesOf(int length) {
    _need(length);
    final bytes = Uint8List.fromList(_bytes.sublist(_at, _at + length));
    _at += length;
    return DecodedBytes(bytes);
  }

  List<Object?> _array(int count, int depth) {
    // Every element takes a byte at least, so a count beyond what is left is a
    // lie, and believing it would be a long loop.
    if (count > _bytes.length - _at) throw const FormatException('cut short');
    return [for (var i = 0; i < count; i++) read(depth + 1)];
  }

  Map<String, Object?> _map(int count, int depth) {
    if (count * 2 > _bytes.length - _at) {
      throw const FormatException('cut short');
    }
    final map = <String, Object?>{};
    for (var i = 0; i < count; i++) {
      final key = read(depth + 1);
      final value = read(depth + 1);
      map[key is String ? key : renderDecoded(key)] = value;
    }
    return map;
  }

  Object? _extension(int length) {
    final type = _signed(1);
    _need(length);
    final data = Uint8List.fromList(_bytes.sublist(_at, _at + length));
    _at += length;
    if (type == -1) {
      final time = _timestamp(data);
      if (time != null) return time;
    }
    return {'ext': type, 'data': DecodedBytes(data)};
  }

  /// The timestamp extension of the specification, in its three sizes, or null
  /// when [data] is not one or names a moment `DateTime` cannot hold.
  static DateTime? _timestamp(Uint8List data) {
    final view = ByteData.sublistView(data);
    final int seconds;
    final int nanos;
    switch (data.length) {
      case 4:
        seconds = view.getUint32(0);
        nanos = 0;
      case 8:
        final packed = view.getUint32(0);
        nanos = packed >> 2;
        seconds = ((packed & 0x3) * 0x100000000) + view.getUint32(4);
      case 12:
        nanos = view.getUint32(0);
        final high = view.getInt32(4);
        if (high < -0x200000 || high >= 0x200000) return null;
        seconds = high * 0x100000000 + view.getUint32(8);
      default:
        return null;
    }
    if (nanos > 999999999) return null;
    try {
      return DateTime.fromMicrosecondsSinceEpoch(
        seconds * 1000000 + nanos ~/ 1000,
        isUtc: true,
      );
    } on Object {
      return null;
    }
  }
}
