import 'dart:typed_data';

/// The wire types of the protobuf encoding.
abstract final class WireType {
  /// A variable length integer.
  static const int varint = 0;

  /// Eight bytes, little endian.
  static const int fixed64 = 1;

  /// A length, then that many bytes.
  static const int lengthDelimited = 2;

  /// The start of a group, which proto2 used for nested messages.
  static const int startGroup = 3;

  /// The end of a group.
  static const int endGroup = 4;

  /// Four bytes, little endian.
  static const int fixed32 = 5;
}

/// How deep messages and groups may nest before the reader gives up.
const int maxProtoDepth = 64;

/// A field as it was written, before anything says what it means.
final class WireField {
  /// Creates a field.
  const WireField(this.number, this.type, this.value);

  /// The field number.
  final int number;

  /// The wire type, one of [WireType].
  final int type;

  /// What the wire type holds: an `int`, or a `BigInt` once the number is too
  /// big for one, for a varint; the eight or four bytes, as they were written,
  /// for a fixed width field; the bytes for a length delimited one; and the
  /// list of fields inside for a group.
  final Object value;
}

/// Reads the fields of a message from [bytes], in the order they were written.
/// Throws a [FormatException] when the bytes are not a protobuf message.
List<WireField> readWireMessage(Uint8List bytes, {int depth = 0}) {
  final reader = _Reader(bytes, depth);
  final fields = <WireField>[];
  while (!reader.atEnd) {
    fields.add(reader.field());
  }
  return fields;
}

/// The varints of a packed run of values, such as a `repeated int32` of proto3.
List<Object> readPackedVarints(Uint8List bytes) {
  final reader = _Reader(bytes, 0);
  final values = <Object>[];
  while (!reader.atEnd) {
    values.add(reader._varint());
  }
  return values;
}

/// The values of a packed run of fixed width values, each [size] bytes.
List<Uint8List> readPackedFixed(Uint8List bytes, int size) {
  if (bytes.length % size != 0) {
    throw const FormatException('a packed run that does not divide');
  }
  return [
    for (var at = 0; at < bytes.length; at += size)
      Uint8List.sublistView(bytes, at, at + size),
  ];
}

/// Joins the two halves of a 64 bit value: an `int` while it is safe to hold in
/// one, a `BigInt` from there on, so that the number is never rounded.
Object joinUnsigned(int high, int low) => high < 0x200000
    ? high * 0x100000000 + low
    : (BigInt.from(high) << 32) | BigInt.from(low);

/// [value], which was written as an unsigned 64 bit varint, as the signed
/// number it stands for.
Object signed64(Object value) {
  if (value is int) return value;
  final big = value as BigInt;
  final result = big >= BigInt.two.pow(63) ? big - BigInt.two.pow(64) : big;
  return _smallest(result);
}

/// [value] with the zigzag encoding of `sint32` and `sint64` undone.
Object zigzag(Object value) {
  if (value is int) {
    return value.isEven ? value ~/ 2 : -((value + 1) ~/ 2);
  }
  final big = value as BigInt;
  return _smallest(
    big.isEven ? big ~/ BigInt.two : -((big + BigInt.one) ~/ BigInt.two),
  );
}

/// The low 32 bits of [value], as an unsigned number.
int low32(Object value) => value is int
    ? value & 0xffffffff
    : (value as BigInt).toUnsigned(32).toInt();

/// The low 32 bits of [value], as a signed number.
int signed32(Object value) {
  final low = low32(value);
  return low >= 0x80000000 ? low - 0x100000000 : low;
}

/// A fixed width field, read as unsigned.
Object unsignedFixed(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  if (bytes.length == 4) return view.getUint32(0, Endian.little);
  return joinUnsigned(
    view.getUint32(4, Endian.little),
    view.getUint32(0, Endian.little),
  );
}

/// An eight byte field, read as signed.
Object signedFixed64(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final high = view.getInt32(4, Endian.little);
  final low = view.getUint32(0, Endian.little);
  if (high >= -0x200000 && high < 0x200000) return high * 0x100000000 + low;
  return (BigInt.from(high) << 32) + BigInt.from(low);
}

Object _smallest(BigInt value) =>
    value.abs() < BigInt.two.pow(53) ? value.toInt() : value;

class _Reader {
  _Reader(this._bytes, this._depth);

  final Uint8List _bytes;
  final int _depth;
  int _at = 0;

  bool get atEnd => _at >= _bytes.length;

  WireField field() {
    final tag = _varint();
    if (tag is! int || tag > 0xffffffff) {
      throw const FormatException('a tag too big to be one');
    }
    final number = tag >> 3;
    final type = tag & 0x7;
    if (number == 0) throw const FormatException('field number 0');
    switch (type) {
      case WireType.varint:
        return WireField(number, type, _varint());
      case WireType.fixed64:
        return WireField(number, type, _take(8));
      case WireType.lengthDelimited:
        final length = _varint();
        if (length is! int) throw const FormatException('a length too big');
        return WireField(number, type, _take(length));
      case WireType.fixed32:
        return WireField(number, type, _take(4));
      case WireType.startGroup:
        return WireField(number, type, _group(number));
    }
    throw FormatException('wire type $type');
  }

  List<WireField> _group(int number) {
    if (_depth + 1 > maxProtoDepth) {
      throw const FormatException('nested too deep');
    }
    final inner = _Reader(_bytes, _depth + 1).._at = _at;
    final fields = <WireField>[];
    while (true) {
      if (inner.atEnd) throw const FormatException('a group never ended');
      final mark = inner._at;
      final tag = inner._varint();
      if (tag is int && (tag & 0x7) == WireType.endGroup) {
        if (tag >> 3 != number) throw const FormatException('wrong group end');
        _at = inner._at;
        return fields;
      }
      inner._at = mark;
      fields.add(inner.field());
    }
  }

  Uint8List _take(int length) {
    if (length < 0 || _at + length > _bytes.length) {
      throw const FormatException('cut short');
    }
    final slice = Uint8List.sublistView(_bytes, _at, _at + length);
    _at += length;
    return slice;
  }

  Object _varint() {
    var low = 0;
    var high = 0;
    for (var i = 0; i < 10; i++) {
      if (_at >= _bytes.length) throw const FormatException('cut short');
      final byte = _bytes[_at++];
      final bits = byte & 0x7f;
      final shift = i * 7;
      if (shift < 28) {
        low |= bits << shift;
      } else if (shift == 28) {
        low |= (bits & 0x0f) << 28;
        high |= bits >> 4;
      } else {
        high |= bits << (shift - 32);
      }
      if ((byte & 0x80) == 0) {
        return joinUnsigned(high & 0xffffffff, low & 0xffffffff);
      }
    }
    throw const FormatException('a varint of more than ten bytes');
  }
}
