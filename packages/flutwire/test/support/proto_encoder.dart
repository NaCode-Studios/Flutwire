import 'dart:convert';
import 'dart:typed_data';

/// Bytes in the protobuf wire format, written by hand for tests. It builds both
/// the messages and the descriptors that describe them.
final class Wire {
  final BytesBuilder _out = BytesBuilder();

  /// A varint field.
  Wire varint(int field, Object value) {
    _tag(field, 0);
    _varint(value);
    return this;
  }

  /// A string field.
  Wire string(int field, String value) => bytes(field, utf8.encode(value));

  /// A length delimited field.
  Wire bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(value.length);
    _out.add(value);
    return this;
  }

  /// A nested message.
  Wire message(int field, Wire inner) => bytes(field, inner.build());

  /// A packed run of varints.
  Wire packed(int field, Iterable<int> values) {
    final inner = Wire();
    values.forEach(inner._varint);
    return bytes(field, inner.build());
  }

  /// A four byte field holding [value] as an unsigned number.
  Wire fixed32(int field, int value) {
    _tag(field, 5);
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _out.add(data.buffer.asUint8List());
    return this;
  }

  /// A four byte field holding a float.
  Wire float32(int field, double value) {
    _tag(field, 5);
    final data = ByteData(4)..setFloat32(0, value, Endian.little);
    _out.add(data.buffer.asUint8List());
    return this;
  }

  /// An eight byte field holding a double.
  Wire double64(int field, double value) {
    _tag(field, 1);
    final data = ByteData(8)..setFloat64(0, value, Endian.little);
    _out.add(data.buffer.asUint8List());
    return this;
  }

  /// An eight byte field holding [value] as an unsigned number.
  Wire fixed64(int field, BigInt value) {
    _tag(field, 1);
    final data = ByteData(8)
      ..setUint32(0, (value & BigInt.from(0xffffffff)).toInt(), Endian.little)
      ..setUint32(4, (value >> 32).toInt(), Endian.little);
    _out.add(data.buffer.asUint8List());
    return this;
  }

  /// A group, as proto2 writes a nested message.
  Wire group(int field, Wire inner) {
    _tag(field, 3);
    _out.add(inner.build());
    _tag(field, 4);
    return this;
  }

  /// Anything, written as it is.
  Wire raw(List<int> value) {
    _out.add(value);
    return this;
  }

  /// The bytes so far.
  Uint8List build() => _out.toBytes();

  void _tag(int field, int type) => _varint((field << 3) | type);

  void _varint(Object value) {
    var number = value is BigInt ? value : BigInt.from(value as int);
    if (number.isNegative) number += BigInt.two.pow(64);
    while (number >= BigInt.from(128)) {
      _out.addByte(((number & BigInt.from(0x7f)) | BigInt.from(0x80)).toInt());
      number >>= 7;
    }
    _out.addByte(number.toInt());
  }
}

/// The types of a field, numbered as `descriptor.proto` does.
abstract final class T {
  static const int double_ = 1;
  static const int float_ = 2;
  static const int int64 = 3;
  static const int uint64 = 4;
  static const int int32 = 5;
  static const int fixed64 = 6;
  static const int fixed32 = 7;
  static const int bool_ = 8;
  static const int string = 9;
  static const int group = 10;
  static const int message = 11;
  static const int bytes = 12;
  static const int uint32 = 13;
  static const int enum_ = 14;
  static const int sfixed32 = 15;
  static const int sfixed64 = 16;
  static const int sint32 = 17;
  static const int sint64 = 18;
}

/// A `FieldDescriptorProto`.
Wire fieldOf(
  String name,
  int number,
  int type, {
  bool repeated = false,
  String? typeName,
}) {
  final field = Wire()
    ..string(1, name)
    ..varint(3, number)
    ..varint(4, repeated ? 3 : 1)
    ..varint(5, type);
  if (typeName != null) field.string(6, typeName);
  return field;
}

/// The descriptor set of the API most tests decode, which is this file:
///
/// ```proto
/// syntax = "proto3";
/// package demo;
/// import "google/protobuf/timestamp.proto";
///
/// enum Kind { KIND_UNKNOWN = 0; KIND_ADMIN = 1; KIND_GUEST = 2; }
/// message Address { string city = 1; string street = 2; }
/// message Person {
///   string name = 1;               int32 id = 2;
///   repeated string emails = 3;    Address address = 4;
///   map<string, int32> scores = 5; Kind kind = 6;
///   repeated int32 lucky = 7;      sint64 delta = 8;
///   double ratio = 9;              bytes avatar = 10;
///   bool active = 11;              fixed32 code = 12;
///   repeated Address previous = 13; google.protobuf.Timestamp joined = 14;
///   uint64 big = 15;               int64 negative = 16;
///   oneof contact { string phone = 17; string fax = 18; }
/// }
/// message PersonLite { string name = 1; int32 id = 2; }
/// message FindRequest { string query = 1; }
/// message Timing {
///   google.protobuf.Duration took = 1; google.protobuf.Timestamp at = 2;
/// }
/// service Directory { rpc Find(FindRequest) returns (Person); }
/// ```
Uint8List sampleDescriptorSet() {
  final timestamp = Wire()
    ..string(1, 'google/protobuf/timestamp.proto')
    ..string(2, 'google.protobuf')
    ..message(
      4,
      Wire()
        ..string(1, 'Timestamp')
        ..message(2, fieldOf('seconds', 1, T.int64))
        ..message(2, fieldOf('nanos', 2, T.int32)),
    );
  final duration = Wire()
    ..string(1, 'google/protobuf/duration.proto')
    ..string(2, 'google.protobuf')
    ..message(
      4,
      Wire()
        ..string(1, 'Duration')
        ..message(2, fieldOf('seconds', 1, T.int64))
        ..message(2, fieldOf('nanos', 2, T.int32)),
    );
  final person = Wire()
    ..string(1, 'Person')
    ..message(2, fieldOf('name', 1, T.string))
    ..message(2, fieldOf('id', 2, T.int32))
    ..message(2, fieldOf('emails', 3, T.string, repeated: true))
    ..message(2, fieldOf('address', 4, T.message, typeName: '.demo.Address'))
    ..message(
      2,
      fieldOf(
        'scores',
        5,
        T.message,
        repeated: true,
        typeName: '.demo.Person.ScoresEntry',
      ),
    )
    ..message(2, fieldOf('kind', 6, T.enum_, typeName: '.demo.Kind'))
    ..message(2, fieldOf('lucky', 7, T.int32, repeated: true))
    ..message(2, fieldOf('delta', 8, T.sint64))
    ..message(2, fieldOf('ratio', 9, T.double_))
    ..message(2, fieldOf('avatar', 10, T.bytes))
    ..message(2, fieldOf('active', 11, T.bool_))
    ..message(2, fieldOf('code', 12, T.fixed32))
    ..message(
      2,
      fieldOf(
        'previous',
        13,
        T.message,
        repeated: true,
        typeName: '.demo.Address',
      ),
    )
    ..message(
      2,
      fieldOf('joined', 14, T.message, typeName: '.google.protobuf.Timestamp'),
    )
    ..message(2, fieldOf('big', 15, T.uint64))
    ..message(2, fieldOf('negative', 16, T.int64))
    ..message(2, fieldOf('phone', 17, T.string))
    ..message(2, fieldOf('fax', 18, T.string))
    ..message(
      3,
      Wire()
        ..string(1, 'ScoresEntry')
        ..message(2, fieldOf('key', 1, T.string))
        ..message(2, fieldOf('value', 2, T.int32))
        ..message(7, Wire()..varint(7, 1)),
    );
  final demo = Wire()
    ..string(1, 'demo.proto')
    ..string(2, 'demo')
    ..string(3, 'google/protobuf/timestamp.proto')
    ..string(3, 'google/protobuf/duration.proto')
    ..message(
      4,
      Wire()
        ..string(1, 'Timing')
        ..message(
          2,
          fieldOf('took', 1, T.message, typeName: '.google.protobuf.Duration'),
        )
        ..message(
          2,
          fieldOf('at', 2, T.message, typeName: '.google.protobuf.Timestamp'),
        ),
    )
    ..message(
      4,
      Wire()
        ..string(1, 'Address')
        ..message(2, fieldOf('city', 1, T.string))
        ..message(2, fieldOf('street', 2, T.string)),
    )
    ..message(4, person)
    ..message(
      4,
      Wire()
        ..string(1, 'PersonLite')
        ..message(2, fieldOf('name', 1, T.string))
        ..message(2, fieldOf('id', 2, T.int32)),
    )
    ..message(
      4,
      Wire()
        ..string(1, 'FindRequest')
        ..message(2, fieldOf('query', 1, T.string)),
    )
    ..message(
      5,
      Wire()
        ..string(1, 'Kind')
        ..message(
          2,
          Wire()
            ..string(1, 'KIND_UNKNOWN')
            ..varint(2, 0),
        )
        ..message(
          2,
          Wire()
            ..string(1, 'KIND_ADMIN')
            ..varint(2, 1),
        )
        ..message(
          2,
          Wire()
            ..string(1, 'KIND_GUEST')
            ..varint(2, 2),
        ),
    )
    ..message(
      6,
      Wire()
        ..string(1, 'Directory')
        ..message(
          2,
          Wire()
            ..string(1, 'Find')
            ..string(2, '.demo.FindRequest')
            ..string(3, '.demo.Person'),
        ),
    )
    ..string(12, 'proto3');
  return (Wire()
        ..message(1, timestamp)
        ..message(1, duration)
        ..message(1, demo))
      .build();
}

/// A `demo.Person` that uses every kind of field.
Uint8List samplePerson() =>
    (Wire()
          ..string(1, 'Ada Lovelace')
          ..varint(2, 42)
          ..string(3, 'ada@example.com')
          ..string(3, 'ada@analytical.engine')
          ..message(
            4,
            Wire()
              ..string(1, 'London')
              ..string(2, "St James's Square"),
          )
          ..message(
            5,
            Wire()
              ..string(1, 'math')
              ..varint(2, 100),
          )
          ..message(
            5,
            Wire()
              ..string(1, 'poetry')
              ..varint(2, 97),
          )
          ..varint(6, 1)
          ..packed(7, [3, 5, 8])
          ..varint(8, 33)
          ..double64(9, 0.5)
          ..bytes(10, [1, 2, 255])
          ..varint(11, 1)
          ..fixed32(12, 3735928559)
          ..message(13, Wire()..string(1, 'Bath'))
          ..message(13, Wire()..string(1, 'Leeds'))
          ..message(
            14,
            Wire()
              ..varint(1, 1700000000)
              ..varint(2, 500000000),
          )
          ..varint(15, BigInt.parse('18446744073709551615'))
          ..varint(16, -9007199254740993)
          ..string(17, '+44 20 7946 0000'))
        .build();
