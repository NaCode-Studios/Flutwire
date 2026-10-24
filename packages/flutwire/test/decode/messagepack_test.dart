import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

const decoder = FlutwireMessagePackDecoder();

FlutwireCall call() => FlutwireCall(
  id: 1,
  method: 'GET',
  uri: Uri.parse('https://api.test/items'),
  source: FlutwireSource.io,
  startedAt: DateTime.utc(2026, 10, 24),
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
);

/// What the decoder says about [bytes], or null when it passes.
String? decode(
  List<int> bytes, {
  String type = 'application/msgpack',
  int? total,
}) => decoder.decode(
  call(),
  FlutwireBody(
    bytes: Uint8List.fromList(bytes),
    totalBytes: total,
    contentType: type,
  ),
  isRequest: false,
);

List<int> ascii(String text) => text.codeUnits;

/// The value [bytes] hold, read back through the text.
Object? value(List<int> bytes) => jsonDecode(decode(bytes)!);

void main() {
  group('the media types it answers for', () {
    test('are the ones that say MessagePack', () {
      for (final type in [
        'application/msgpack',
        'application/x-msgpack',
        'application/vnd.msgpack',
        'application/vnd.api+msgpack',
        'application/msgpack; charset=binary',
      ]) {
        expect(decode([0x01], type: type), '1', reason: type);
      }
    });

    test('are not anything else', () {
      for (final type in [
        'application/json',
        'application/octet-stream',
        'text/plain',
      ]) {
        expect(decode([0x01], type: type), isNull, reason: type);
      }
    });

    test('are not missing', () {
      final text = decoder.decode(
        call(),
        FlutwireBody(bytes: Uint8List.fromList([1])),
        isRequest: false,
      );

      expect(text, isNull);
    });

    test('are named MessagePack', () {
      expect(decoder.name, 'MessagePack');
    });
  });

  group('the example of the specification', () {
    test('is {"compact": true, "schema": 0}', () {
      final bytes = [
        0x82,
        0xa7,
        ...ascii('compact'),
        0xc3,
        0xa6,
        ...ascii('schema'),
        0x00,
      ];

      expect(decode(bytes), '{\n  "compact": true,\n  "schema": 0\n}');
    });
  });

  group('integers', () {
    test('fit in a byte, as a fixint', () {
      expect(value([0x00]), 0);
      expect(value([0x7f]), 127);
      expect(value([0xff]), -1);
      expect(value([0xe0]), -32);
    });

    test('are written in the width they need', () {
      expect(value([0xcc, 0xff]), 255);
      expect(value([0xcd, 0x01, 0x00]), 256);
      expect(value([0xce, 0x00, 0x01, 0x00, 0x00]), 65536);
      expect(value([0xcf, 0, 0, 0, 1, 0, 0, 0, 0]), 4294967296);
      expect(value([0xd0, 0x80]), -128);
      expect(value([0xd1, 0x80, 0x00]), -32768);
      expect(value([0xd2, 0x80, 0, 0, 0]), -2147483648);
      expect(value([0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe]), -2);
    });

    test('keep every digit of a 64 bit number', () {
      expect(decode([0xcf, ...List.filled(8, 0xff)]), '18446744073709551615');
      expect(decode([0xd3, 0x80, 0, 0, 0, 0, 0, 0, 0]), '-9223372036854775808');
      expect(decode([0xcf, 0x00, 0x20, 0, 0, 0, 0, 0, 0]), '9007199254740992');
      expect(
        decode([0xcf, 0x00, 0x1f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        '9007199254740991',
      );
    });
  });

  group('the other plain values', () {
    test('are nil and the booleans', () {
      expect(decode([0xc0]), 'null');
      expect(decode([0xc2]), 'false');
      expect(decode([0xc3]), 'true');
    });

    test('are floats of both sizes', () {
      expect(decode([0xca, 0x3f, 0x80, 0x00, 0x00]), '1.0');
      expect(decode([0xcb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0]), '1.0');
      expect(
        decode([0xcb, 0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18]),
        '3.141592653589793',
      );
    });

    test('are strings of every length class, in UTF-8', () {
      expect(decode([0xa0]), '""');
      expect(decode([0xa3, ...ascii('abc')]), '"abc"');
      expect(decode([0xd9, 0x03, ...ascii('abc')]), '"abc"');
      expect(decode([0xda, 0x00, 0x03, ...ascii('abc')]), '"abc"');
      expect(decode([0xdb, 0x00, 0x00, 0x00, 0x03, ...ascii('abc')]), '"abc"');
      expect(decode([0xa2, 0xc3, 0xa9]), '"é"');
    });

    test('are binary, written as hex', () {
      expect(decode([0xc4, 0x03, 0x01, 0x02, 0x03]), '"01 02 03"');
      expect(decode([0xc5, 0x00, 0x01, 0xff]), '"ff"');
    });
  });

  group('containers', () {
    test('are arrays', () {
      expect(value([0x93, 0x01, 0x02, 0x03]), [1, 2, 3]);
      expect(value([0xdc, 0x00, 0x02, 0x01, 0x02]), [1, 2]);
      expect(value([0x90]), <Object?>[]);
    });

    test('are maps, with keys that are not strings written as text', () {
      expect(value([0x81, 0x01, 0xa1, 0x61]), {'1': 'a'});
      expect(value([0xde, 0x00, 0x01, 0xc3, 0x05]), {'true': 5});
      expect(value([0x80]), <String, Object?>{});
    });

    test('nest', () {
      final bytes = [
        0x81,
        0xa4,
        ...ascii('rows'),
        0x92,
        0x81,
        0xa1,
        0x61,
        0x01,
        0x81,
        0xa1,
        0x61,
        0x02,
      ];

      expect(value(bytes), {
        'rows': [
          {'a': 1},
          {'a': 2},
        ],
      });
    });

    test('may follow one another, as the values of a stream', () {
      expect(value([0x01, 0x02, 0xa1, 0x61]), [1, 2, 'a']);
    });
  });

  group('extensions', () {
    test('are a type number and the bytes', () {
      expect(value([0xd4, 0x05, 0xaa]), {'ext': 5, 'data': 'aa'});
      expect(value([0xc7, 0x03, 0x7f, 1, 2, 3]), {
        'ext': 127,
        'data': '01 02 03',
      });
    });

    test('of type -1 are timestamps, in all three sizes', () {
      // 1700000000 seconds, as a 32 bit number.
      expect(
        decode([0xd6, 0xff, 0x65, 0x53, 0xf1, 0x00]),
        '"2023-11-14T22:13:20.000Z"',
      );
      // 500000000 nanoseconds above it, packed with the seconds in 64 bits.
      final packed = (BigInt.from(500000000) << 34) | BigInt.from(1700000000);
      final eight = [
        for (var shift = 56; shift >= 0; shift -= 8)
          ((packed >> shift) & BigInt.from(0xff)).toInt(),
      ];
      expect(decode([0xd7, 0xff, ...eight]), '"2023-11-14T22:13:20.500Z"');
      // And in 96 bits, with the seconds signed: one second before the epoch.
      expect(
        decode([0xc7, 0x0c, 0xff, 0, 0, 0, 0, ...List.filled(8, 0xff)]),
        '"1969-12-31T23:59:59.000Z"',
      );
    });

    test('of type -1 that are not timestamps stay extensions', () {
      expect(value([0xd5, 0xff, 0x01, 0x02]), {'ext': -1, 'data': '01 02'});
    });
  });

  group('what it leaves alone', () {
    test('is a body that was cut', () {
      final bytes = [0x82, 0xa7, ...ascii('compact'), 0xc3];

      expect(decode(bytes, total: 40), isNull);
    });

    test('is a body that ends in the middle of a value', () {
      expect(decode([0x82, 0xa7, 0x63]), isNull);
      expect(decode([0xcd, 0x01]), isNull);
      expect(decode([0xd9, 0x05, 0x61]), isNull);
    });

    test('is a tag the specification never uses', () {
      expect(decode([0xc1]), isNull);
    });

    test('is a count that promises more than there is', () {
      expect(decode([0xdd, 0xff, 0xff, 0xff, 0xff]), isNull);
      expect(decode([0xdf, 0xff, 0xff, 0xff, 0xff, 0x01]), isNull);
    });

    test('is a document nested far deeper than is sane', () {
      expect(decode(List.filled(200, 0x91)), isNull);
    });

    test('is an empty body', () {
      expect(decode([]), isNull);
    });
  });
}
