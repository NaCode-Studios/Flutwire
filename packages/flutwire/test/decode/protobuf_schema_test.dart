import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/decode/protobuf/schema.dart';

import '../support/proto_encoder.dart';

void main() {
  late ProtoSchema schema;

  setUp(() => schema = ProtoSchema.fromDescriptorSet(sampleDescriptorSet()));

  group('the messages of a descriptor set', () {
    test('are found by their full name', () {
      expect(schema.message('demo.Person'), isNotNull);
      expect(schema.message('demo.Address'), isNotNull);
      expect(schema.message('google.protobuf.Timestamp'), isNotNull);
      expect(schema.message('demo.Missing'), isNull);
    });

    test('know their fields by number', () {
      final person = schema.message('demo.Person')!;

      expect(person.fields[1]!.name, 'name');
      expect(person.fields[1]!.type, ProtoType.string);
      expect(person.fields[3]!.isRepeated, isTrue);
      expect(person.fields[4]!.type, ProtoType.message);
      expect(person.fields[4]!.typeName, 'demo.Address');
      expect(person.fields[6]!.type, ProtoType.enumeration);
      expect(person.fields[8]!.type, ProtoType.sint64);
      expect(person.fields[99], isNull);
    });

    test('include the entry type of a map, marked as one', () {
      final entry = schema.message('demo.Person.ScoresEntry')!;

      expect(entry.isMapEntry, isTrue);
      expect(entry.fields[1]!.name, 'key');
      expect(entry.fields[2]!.type, ProtoType.int32);
      expect(schema.message('demo.Person')!.isMapEntry, isFalse);
    });
  });

  group('the enums', () {
    test('are found by full name, with their values by number', () {
      expect(schema.enumeration('demo.Kind'), {
        0: 'KIND_UNKNOWN',
        1: 'KIND_ADMIN',
        2: 'KIND_GUEST',
      });
      expect(schema.enumeration('demo.Nothing'), isNull);
    });
  });

  group('the services', () {
    test('give a method its input and output types', () {
      final method = schema.methodAt('/demo.Directory/Find')!;

      expect(method.inputType, 'demo.FindRequest');
      expect(method.outputType, 'demo.Person');
    });

    test('are found with or without the leading slash', () {
      expect(schema.methodAt('demo.Directory/Find'), isNotNull);
    });

    test('are not made up for a path they do not have', () {
      expect(schema.methodAt('/demo.Directory/Lose'), isNull);
      expect(schema.methodAt('/other.Service/Find'), isNull);
      expect(schema.methodAt('/'), isNull);
    });
  });

  group('a descriptor set that is not one', () {
    test('is rejected', () {
      expect(
        () => ProtoSchema.fromDescriptorSet([0x0a, 0xff, 0x01]),
        throwsFormatException,
      );
    });

    test('is an empty one when it is empty', () {
      final empty = ProtoSchema.fromDescriptorSet(Uint8List(0));

      expect(empty.message('demo.Person'), isNull);
    });

    test('keeps the rest when a field has no name or number', () {
      final broken =
          (Wire()..message(
                1,
                Wire()
                  ..string(1, 'x.proto')
                  ..string(2, 'x')
                  ..message(
                    4,
                    Wire()
                      ..string(1, 'M')
                      ..message(2, Wire()..string(1, 'nameless')),
                  ),
              ))
              .build();

      final partial = ProtoSchema.fromDescriptorSet(broken);

      expect(partial.message('x.M')!.fields, isEmpty);
    });
  });
}
