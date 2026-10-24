import 'dart:convert';
import 'dart:typed_data';

import 'wire.dart';

/// The kinds of value a field can hold, numbered as `descriptor.proto` does.
enum ProtoType {
  /// `double`.
  double(1),

  /// `float`.
  float(2),

  /// `int64`.
  int64(3),

  /// `uint64`.
  uint64(4),

  /// `int32`.
  int32(5),

  /// `fixed64`.
  fixed64(6),

  /// `fixed32`.
  fixed32(7),

  /// `bool`.
  bool(8),

  /// `string`.
  string(9),

  /// A group.
  group(10),

  /// A message.
  message(11),

  /// `bytes`.
  bytes(12),

  /// `uint32`.
  uint32(13),

  /// An enum.
  enumeration(14),

  /// `sfixed32`.
  sfixed32(15),

  /// `sfixed64`.
  sfixed64(16),

  /// `sint32`.
  sint32(17),

  /// `sint64`.
  sint64(18);

  const ProtoType(this.number);

  /// The number `descriptor.proto` gives it.
  final int number;

  /// The type with the given [number], or null.
  static ProtoType? of(int number) {
    for (final type in values) {
      if (type.number == number) return type;
    }
    return null;
  }
}

/// What a type allows.
extension ProtoTypeRules on ProtoType {
  /// Whether a repeated field of this type may be packed: written as one
  /// length delimited run of values.
  bool get isPackable => switch (this) {
    ProtoType.string ||
    ProtoType.group ||
    ProtoType.message ||
    ProtoType.bytes => false,
    _ => true,
  };
}

/// A field of a message.
final class ProtoField {
  /// Creates a field description.
  const ProtoField({
    required this.name,
    required this.number,
    required this.type,
    required this.isRepeated,
    this.typeName,
  });

  /// The name in the `.proto` file.
  final String name;

  /// The field number.
  final int number;

  /// What it holds.
  final ProtoType type;

  /// Whether it is `repeated`.
  final bool isRepeated;

  /// For a message, a group or an enum, the full name of the type, without the
  /// dot a descriptor writes in front.
  final String? typeName;
}

/// A message type.
final class ProtoMessage {
  /// Creates a message description.
  const ProtoMessage({
    required this.fullName,
    required this.fields,
    required this.isMapEntry,
  });

  /// The name with its package and the messages it is nested in.
  final String fullName;

  /// The fields by number.
  final Map<int, ProtoField> fields;

  /// Whether this is the entry type the compiler makes for a `map` field.
  final bool isMapEntry;
}

/// A method of a service.
final class ProtoMethod {
  /// Creates a method description.
  const ProtoMethod({required this.inputType, required this.outputType});

  /// The full name of the message the method takes.
  final String inputType;

  /// The full name of the message the method answers with.
  final String outputType;
}

/// What a descriptor set says about the messages, enums and services of an API.
///
/// It is read from the bytes of a `FileDescriptorSet`, which `protoc` writes
/// with `--descriptor_set_out`, `--include_imports` included so that every type
/// a message uses is there.
final class ProtoSchema {
  ProtoSchema._(this._messages, this._enums, this._methods);

  /// Reads a descriptor set. Throws a [FormatException] when [bytes] are not
  /// one.
  factory ProtoSchema.fromDescriptorSet(List<int> bytes) {
    final messages = <String, ProtoMessage>{};
    final enums = <String, Map<int, String>>{};
    final methods = <String, ProtoMethod>{};
    final set = readWireMessage(Uint8List.fromList(bytes));
    for (final file in set.where(
      (f) => f.number == 1 && f.type == WireType.lengthDelimited,
    )) {
      _readFile(
        readWireMessage(file.value as Uint8List),
        messages,
        enums,
        methods,
      );
    }
    return ProtoSchema._(messages, enums, methods);
  }

  final Map<String, ProtoMessage> _messages;
  final Map<String, Map<int, String>> _enums;
  final Map<String, ProtoMethod> _methods;

  /// The message with the given full name, such as `demo.Person`, or null.
  ProtoMessage? message(String fullName) => _messages[fullName];

  /// The names of the values of the enum with the given full name, by number,
  /// or null.
  Map<int, String>? enumeration(String fullName) => _enums[fullName];

  /// The method that a gRPC [path], such as `/demo.Directory/Find`, names, or
  /// null.
  ProtoMethod? methodAt(String path) {
    final trimmed = path.startsWith('/') ? path.substring(1) : path;
    return _methods[trimmed.replaceFirst('/', '.')] ?? _methods[trimmed];
  }

  static void _readFile(
    List<WireField> file,
    Map<String, ProtoMessage> messages,
    Map<String, Map<int, String>> enums,
    Map<String, ProtoMethod> methods,
  ) {
    final package = _string(file, 2) ?? '';
    final prefix = package.isEmpty ? '' : '$package.';
    for (final message in _nested(file, 4)) {
      _readMessage(message, prefix, messages, enums);
    }
    for (final enumeration in _nested(file, 5)) {
      _readEnum(enumeration, prefix, enums);
    }
    for (final service in _nested(file, 6)) {
      final name = '$prefix${_string(service, 1) ?? ''}';
      for (final method in _nested(service, 2)) {
        final methodName = _string(method, 1);
        final input = _typeName(method, 2);
        final output = _typeName(method, 3);
        if (methodName == null || input == null || output == null) continue;
        methods['$name.$methodName'] = ProtoMethod(
          inputType: input,
          outputType: output,
        );
      }
    }
  }

  static void _readMessage(
    List<WireField> message,
    String prefix,
    Map<String, ProtoMessage> messages,
    Map<String, Map<int, String>> enums,
  ) {
    final fullName = '$prefix${_string(message, 1) ?? ''}';
    final fields = <int, ProtoField>{};
    for (final field in _nested(message, 2)) {
      final number = _int(field, 3);
      final type = ProtoType.of(_int(field, 5) ?? 0);
      final name = _string(field, 1);
      if (number == null || type == null || name == null) continue;
      fields[number] = ProtoField(
        name: name,
        number: number,
        type: type,
        isRepeated: _int(field, 4) == 3,
        typeName: _typeName(field, 6),
      );
    }
    final options = _nested(message, 7).firstOrNull;
    messages[fullName] = ProtoMessage(
      fullName: fullName,
      fields: fields,
      isMapEntry: options != null && _int(options, 7) == 1,
    );
    for (final nested in _nested(message, 3)) {
      _readMessage(nested, '$fullName.', messages, enums);
    }
    for (final enumeration in _nested(message, 4)) {
      _readEnum(enumeration, '$fullName.', enums);
    }
  }

  static void _readEnum(
    List<WireField> enumeration,
    String prefix,
    Map<String, Map<int, String>> enums,
  ) {
    final values = <int, String>{};
    for (final value in _nested(enumeration, 2)) {
      final name = _string(value, 1);
      final number = _int(value, 2);
      if (name != null && number != null) {
        values.putIfAbsent(number, () => name);
      }
    }
    enums['$prefix${_string(enumeration, 1) ?? ''}'] = values;
  }

  /// The nested messages written under field [number].
  static Iterable<List<WireField>> _nested(
    List<WireField> fields,
    int number,
  ) => fields
      .where((f) => f.number == number && f.type == WireType.lengthDelimited)
      .map((f) => readWireMessage(f.value as Uint8List));

  static String? _string(List<WireField> fields, int number) {
    for (final f in fields) {
      if (f.number == number && f.type == WireType.lengthDelimited) {
        return utf8.decode(f.value as Uint8List, allowMalformed: true);
      }
    }
    return null;
  }

  /// A type name as a descriptor writes it, `.demo.Person`, without the dot.
  static String? _typeName(List<WireField> fields, int number) {
    final name = _string(fields, number);
    if (name == null) return null;
    return name.startsWith('.') ? name.substring(1) : name;
  }

  static int? _int(List<WireField> fields, int number) {
    for (final f in fields) {
      if (f.number == number && f.type == WireType.varint) {
        final value = f.value;
        return value is int ? value : null;
      }
    }
    return null;
  }
}
