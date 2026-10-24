import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/decode/protobuf/wire.dart';

import '../support/proto_encoder.dart';

List<WireField> read(List<int> bytes) =>
    readWireMessage(Uint8List.fromList(bytes));

void main() {
  group('the examples of the encoding guide', () {
    test('field 1 holding 150 is 08 96 01', () {
      final fields = read([0x08, 0x96, 0x01]);

      expect(fields.single.number, 1);
      expect(fields.single.type, WireType.varint);
      expect(fields.single.value, 150);
    });

    test('field 2 holding "testing" is 12 07 followed by the text', () {
      final fields = read([0x12, 0x07, ...utf8.encode('testing')]);

      expect(fields.single.number, 2);
      expect(fields.single.type, WireType.lengthDelimited);
      expect(utf8.decode(fields.single.value as Uint8List), 'testing');
    });

    test('a message in field 3 holding field 1 as 150 is 1a 03 08 96 01', () {
      final fields = read([0x1a, 0x03, 0x08, 0x96, 0x01]);
      final inner = readWireMessage(fields.single.value as Uint8List);

      expect(fields.single.number, 3);
      expect(inner.single.value, 150);
    });
  });

  group('varints', () {
    test('are read in every width up to ten bytes', () {
      expect(read([0x08, 0x00]).single.value, 0);
      expect(read([0x08, 0x7f]).single.value, 127);
      expect(read([0x08, 0x80, 0x01]).single.value, 128);
      expect(
        read([0x08, 0xff, 0xff, 0xff, 0xff, 0x0f]).single.value,
        4294967295,
      );
      expect(
        read([0x08, ...List.filled(9, 0xff), 0x01]).single.value,
        BigInt.parse('18446744073709551615'),
      );
    });

    test('hold a number up to 2^53 in an int and the rest in a BigInt', () {
      final safe = Wire()..varint(1, 9007199254740991);
      final unsafe = Wire()..varint(1, BigInt.parse('9007199254740993'));

      expect(readWireMessage(safe.build()).single.value, 9007199254740991);
      expect(
        readWireMessage(unsafe.build()).single.value,
        BigInt.parse('9007199254740993'),
      );
    });

    test('are signed or zigzag decoded on request', () {
      expect(signed64(150), 150);
      expect(signed64(BigInt.parse('18446744073709551615')), -1);
      expect(signed64(BigInt.parse('18446744073709551614')), -2);
      expect(
        signed64(BigInt.parse('9223372036854775808')),
        BigInt.parse('-9223372036854775808'),
      );
      expect(zigzag(0), 0);
      expect(zigzag(1), -1);
      expect(zigzag(2), 1);
      expect(zigzag(4294967294), 2147483647);
      expect(zigzag(4294967295), -2147483648);
      expect(
        zigzag(BigInt.parse('18446744073709551615')),
        BigInt.parse('-9223372036854775808'),
      );
    });

    test('narrow to 32 bits the way int32 does, negative numbers included', () {
      expect(signed32(BigInt.parse('18446744073709551615')), -1);
      expect(signed32(5), 5);
      expect(low32(BigInt.parse('18446744073709551615')), 4294967295);
      expect(low32(4294967296 + 7), 7);
    });

    test('that run past ten bytes are not varints', () {
      expect(
        () => read([0x08, ...List.filled(11, 0xff)]),
        throwsFormatException,
      );
    });

    test('that are cut short are not varints', () {
      expect(() => read([0x08, 0x80]), throwsFormatException);
    });
  });

  group('fixed width fields', () {
    test('are held as the bytes that were written', () {
      final bytes =
          (Wire()
                ..fixed32(1, 0xdeadbeef)
                ..fixed64(2, BigInt.parse('18446744073709551615')))
              .build();
      final fields = readWireMessage(bytes);

      expect(fields[0].type, WireType.fixed32);
      expect(unsignedFixed(fields[0].value as Uint8List), 0xdeadbeef);
      expect(fields[1].type, WireType.fixed64);
      expect(
        unsignedFixed(fields[1].value as Uint8List),
        BigInt.parse('18446744073709551615'),
      );
      expect(signedFixed64(fields[1].value as Uint8List), -1);
    });

    test('that are cut short are not fields', () {
      expect(() => read([0x0d, 0x01, 0x02]), throwsFormatException);
      expect(() => read([0x09, 0x01]), throwsFormatException);
    });
  });

  group('groups', () {
    test('hold the fields between their start and their end', () {
      final bytes =
          (Wire()..group(
                5,
                Wire()
                  ..varint(1, 7)
                  ..string(2, 'x'),
              ))
              .build();
      final fields = readWireMessage(bytes);
      final inner = fields.single.value as List<WireField>;

      expect(fields.single.type, WireType.startGroup);
      expect(inner.map((f) => f.number), [1, 2]);
    });

    test('that never end are not groups', () {
      expect(() => read([0x2b, 0x08, 0x01]), throwsFormatException);
    });

    test('that end with the wrong number are not groups', () {
      expect(() => read([0x2b, 0x08, 0x01, 0x34]), throwsFormatException);
    });

    test('nested past the limit are not read', () {
      final deep = Wire();
      var inner = Wire()..varint(1, 1);
      for (var i = 0; i < 100; i++) {
        inner = Wire()..group(1, inner);
      }
      deep.raw(inner.build());

      expect(() => readWireMessage(deep.build()), throwsFormatException);
    });
  });

  group('packed runs', () {
    test('of varints are read one after the other', () {
      expect(readPackedVarints(Uint8List.fromList([3, 0x8e, 0x02, 5])), [
        3,
        270,
        5,
      ]);
    });

    test('of fixed width values are cut at the width', () {
      final run = Uint8List.fromList([1, 0, 0, 0, 2, 0, 0, 0]);

      expect(readPackedFixed(run, 4).map(unsignedFixed), [1, 2]);
    });

    test('that do not divide into values are not runs', () {
      expect(() => readPackedFixed(Uint8List(5), 4), throwsFormatException);
    });
  });

  group('what is not a message', () {
    test('is a tag with field number 0', () {
      expect(() => read([0x00, 0x01]), throwsFormatException);
    });

    test('is a wire type that does not exist', () {
      expect(() => read([0x0e, 0x01]), throwsFormatException);
      expect(() => read([0x0f, 0x01]), throwsFormatException);
    });

    test('is a lone group end', () {
      expect(() => read([0x0c]), throwsFormatException);
    });

    test('is a length that runs past the end', () {
      expect(() => read([0x0a, 0x05, 0x61]), throwsFormatException);
    });

    test('is a tag too big to be one', () {
      expect(
        () => read([0xff, 0xff, 0xff, 0xff, 0xff, 0x01]),
        throwsFormatException,
      );
    });
  });
}
