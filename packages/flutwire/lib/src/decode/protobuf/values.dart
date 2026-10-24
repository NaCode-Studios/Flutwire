import 'dart:convert';
import 'dart:typed_data';

import '../decoded_text.dart';
import 'schema.dart';
import 'wire.dart';

/// Turns the bytes of a protobuf message into the values a renderer writes.
///
/// When the schema knows the message its fields come out by name and typed:
/// enums by name, maps as objects, packed runs as lists. Without a schema the
/// fields come out by number, and what the wire cannot tell apart is guessed
/// the way `protoc --decode_raw` does: a length delimited field is text when
/// it reads as text, a message when it reads as one, and bytes otherwise.
final class ProtoValues {
  /// Creates a converter that looks types up in [schema], if there is one.
  const ProtoValues(this.schema);

  /// What the types are, or null to go by field number.
  final ProtoSchema? schema;

  /// [bytes] as a message of [type], or by field number when [type] is null.
  /// Throws a [FormatException] when [bytes] are not a message.
  Map<String, Object?> message(
    Uint8List bytes,
    ProtoMessage? type, [
    int depth = 0,
  ]) {
    if (depth > maxProtoDepth) throw const FormatException('nested too deep');
    return _fields(readWireMessage(bytes, depth: depth), type, depth);
  }

  Map<String, Object?> _fields(
    List<WireField> fields,
    ProtoMessage? type,
    int depth,
  ) {
    final out = <String, Object?>{};
    for (final field in fields) {
      final definition = type?.fields[field.number];
      if (definition == null) {
        // A field the schema does not know, or no schema at all.
        final key = type == null
            ? '${field.number}'
            : '<unknown ${field.number}>';
        _put(out, key, _raw(field, depth));
        continue;
      }
      final entry = _mapEntry(definition);
      if (entry != null && field.type == WireType.lengthDelimited) {
        final map = out.putIfAbsent(definition.name, () => <String, Object?>{});
        _putEntry(
          map as Map<String, Object?>,
          entry,
          field.value as Uint8List,
          depth,
        );
        continue;
      }
      final value = _field(definition, field, depth);
      if (definition.isRepeated) {
        final list = out.putIfAbsent(definition.name, () => <Object?>[]);
        (list as List<Object?>).addAll(
          value is _Packed ? value.items : [value],
        );
      } else {
        out[definition.name] = value;
      }
    }
    out.updateAll((_, value) => value is _Many ? value.items : value);
    return out;
  }

  /// Adds [value] under [key], keeping every value when the same field shows up
  /// more than once.
  static void _put(Map<String, Object?> out, String key, Object? value) {
    if (!out.containsKey(key)) {
      out[key] = value;
      return;
    }
    final before = out[key];
    if (before is _Many) {
      before.items.add(value);
    } else {
      out[key] = _Many([before, value]);
    }
  }

  ProtoMessage? _mapEntry(ProtoField definition) {
    if (!definition.isRepeated || definition.type != ProtoType.message) {
      return null;
    }
    final type = schema?.message(definition.typeName ?? '');
    return type != null && type.isMapEntry ? type : null;
  }

  void _putEntry(
    Map<String, Object?> map,
    ProtoMessage entry,
    Uint8List bytes,
    int depth,
  ) {
    final fields = readWireMessage(bytes, depth: depth + 1);
    final keyDefinition = entry.fields[1];
    final valueDefinition = entry.fields[2];
    if (keyDefinition == null || valueDefinition == null) return;
    Object? key = '';
    Object? value;
    for (final field in fields) {
      if (field.number == 1) key = _field(keyDefinition, field, depth + 1);
      if (field.number == 2) value = _field(valueDefinition, field, depth + 1);
    }
    map[key is String ? key : '$key'] = value;
  }

  Object? _field(ProtoField definition, WireField field, int depth) {
    final type = definition.type;
    if (definition.isRepeated &&
        type.isPackable &&
        field.type == WireType.lengthDelimited) {
      return _Packed(_unpack(definition, field.value as Uint8List, depth));
    }
    final expected = switch (type) {
      ProtoType.int32 ||
      ProtoType.int64 ||
      ProtoType.uint32 ||
      ProtoType.uint64 ||
      ProtoType.sint32 ||
      ProtoType.sint64 ||
      ProtoType.bool ||
      ProtoType.enumeration => WireType.varint,
      ProtoType.float ||
      ProtoType.fixed32 ||
      ProtoType.sfixed32 => WireType.fixed32,
      ProtoType.double ||
      ProtoType.fixed64 ||
      ProtoType.sfixed64 => WireType.fixed64,
      ProtoType.string ||
      ProtoType.bytes ||
      ProtoType.message => WireType.lengthDelimited,
      ProtoType.group => WireType.startGroup,
    };
    // A field written with a wire type its declaration does not allow is shown
    // as the wire has it, rather than guessed at.
    if (field.type != expected) return _raw(field, depth);
    return switch (field.value) {
      final Uint8List bytes when expected == WireType.lengthDelimited =>
        _lengthDelimited(definition, bytes, depth),
      final Uint8List bytes => _fixed(type, bytes),
      final List<WireField> group => _wellKnown(
        definition.typeName,
        _fields(group, schema?.message(definition.typeName ?? ''), depth + 1),
      ),
      final Object varint => _varint(definition, varint),
    };
  }

  Object? _lengthDelimited(ProtoField definition, Uint8List bytes, int depth) {
    switch (definition.type) {
      case ProtoType.string:
        return utf8.decode(bytes, allowMalformed: true);
      case ProtoType.bytes:
        return DecodedBytes(Uint8List.fromList(bytes));
      default:
        final name = definition.typeName;
        final nested = message(bytes, schema?.message(name ?? ''), depth + 1);
        return _wellKnown(name, nested);
    }
  }

  List<Object?> _unpack(ProtoField definition, Uint8List bytes, int depth) =>
      switch (definition.type) {
        ProtoType.float || ProtoType.fixed32 || ProtoType.sfixed32 => [
          for (final item in readPackedFixed(bytes, 4))
            _fixed(definition.type, item),
        ],
        ProtoType.double || ProtoType.fixed64 || ProtoType.sfixed64 => [
          for (final item in readPackedFixed(bytes, 8))
            _fixed(definition.type, item),
        ],
        _ => [
          for (final item in readPackedVarints(bytes))
            _varint(definition, item),
        ],
      };

  Object? _varint(ProtoField definition, Object value) {
    switch (definition.type) {
      case ProtoType.int64:
        return signed64(value);
      case ProtoType.int32:
        return signed32(value);
      case ProtoType.uint32:
        return low32(value);
      case ProtoType.sint32 || ProtoType.sint64:
        return zigzag(value);
      case ProtoType.bool:
        return value is int ? value != 0 : value != BigInt.zero;
      case ProtoType.enumeration:
        final number = signed32(value);
        return schema?.enumeration(definition.typeName ?? '')?[number] ??
            number;
      default:
        return value;
    }
  }

  static Object? _fixed(ProtoType type, Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    return switch (type) {
      ProtoType.float => view.getFloat32(0, Endian.little),
      ProtoType.double => view.getFloat64(0, Endian.little),
      ProtoType.sfixed32 => view.getInt32(0, Endian.little),
      ProtoType.sfixed64 => signedFixed64(bytes),
      _ => unsignedFixed(bytes),
    };
  }

  /// A field read with no help from a schema.
  Object? _raw(WireField field, int depth) {
    switch (field.type) {
      case WireType.varint:
        return field.value;
      case WireType.fixed32 || WireType.fixed64:
        final bytes = field.value as Uint8List;
        final hex = [
          for (final byte in bytes.reversed)
            byte.toRadixString(16).padLeft(2, '0'),
        ].join();
        return '0x$hex';
      case WireType.startGroup:
        return _fields(field.value as List<WireField>, null, depth + 1);
      default:
        return _guess(field.value as Uint8List, depth);
    }
  }

  /// What a length delimited field with no declared type most likely is.
  Object? _guess(Uint8List bytes, int depth) {
    if (bytes.isEmpty) return '';
    final text = _text(bytes);
    Map<String, Object?>? nested;
    if (depth < maxProtoDepth) {
      try {
        nested = message(bytes, null, depth + 1);
      } on FormatException {
        nested = null;
      }
    }
    // Text that has a line break in it is as likely to be the bytes of a
    // message, whose tags are often control characters, as a paragraph.
    if (text != null &&
        !(nested != null && RegExp(r'[\t\n\r]').hasMatch(text))) {
      return text;
    }
    return nested ?? DecodedBytes(Uint8List.fromList(bytes));
  }

  /// The text [bytes] hold, if they hold nothing but text.
  static String? _text(Uint8List bytes) {
    final String text;
    try {
      text = const Utf8Decoder().convert(bytes);
    } on FormatException {
      return null;
    }
    for (final unit in text.codeUnits) {
      if (unit == 0x7f ||
          (unit < 0x20 && unit != 9 && unit != 10 && unit != 13)) {
        return null;
      }
    }
    return text;
  }

  /// The two well known types that are better as a string than as the pair of
  /// numbers they are written as.
  static Object? _wellKnown(String? name, Map<String, Object?> fields) {
    if (name != 'google.protobuf.Timestamp' &&
        name != 'google.protobuf.Duration') {
      return fields;
    }
    final seconds = fields['seconds'];
    final nanos = fields['nanos'];
    if ((seconds != null && seconds is! int) ||
        (nanos != null && nanos is! int)) {
      return fields;
    }
    final s = (seconds as int?) ?? 0;
    final n = (nanos as int?) ?? 0;
    if (name == 'google.protobuf.Duration') {
      final sign = s < 0 || n < 0 ? '-' : '';
      final fraction = n
          .abs()
          .toString()
          .padLeft(9, '0')
          .replaceFirst(RegExp(r'0+$'), '');
      return '$sign${s.abs()}${fraction.isEmpty ? '' : '.$fraction'}s';
    }
    try {
      return DateTime.fromMicrosecondsSinceEpoch(
        s * 1000000 + n ~/ 1000,
        isUtc: true,
      );
    } on Object {
      return fields;
    }
  }
}

/// The values of a packed run, to be added to the list of the field.
final class _Packed {
  const _Packed(this.items);

  final List<Object?> items;
}

/// A field that showed up more than once in a message with no schema.
final class _Many {
  const _Many(this.items);

  final List<Object?> items;
}
