import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

// What the other Protobuf tests read is built by hand, with an encoder written
// for them, so a misreading of the format could sit on both sides. This one
// reads what protoc itself wrote: the descriptor set, and messages serialised
// by the code protoc generates. `test/fixtures/protoc/make.py` writes them.

Uint8List fixture(String name) =>
    File('test/fixtures/protoc/$name').readAsBytesSync();

FlutwireCall call(String path) => FlutwireCall(
  id: 1,
  method: 'POST',
  uri: Uri.parse('https://api.test$path'),
  source: FlutwireSource.io,
  startedAt: DateTime.utc(2026, 10, 24),
  request: FlutwireRequest(
    headers: FlutwireHeaders.empty,
    body: FlutwireBody.empty(),
  ),
);

String? decode(
  FlutwireBodyDecoder decoder,
  List<int> bytes, {
  String path = '/x',
  String type = 'application/x-protobuf',
  bool isRequest = false,
}) => decoder.decode(
  call(path),
  FlutwireBody(bytes: Uint8List.fromList(bytes), contentType: type),
  isRequest: isRequest,
);

List<int> frame(List<int> payload) => [
  0,
  (payload.length >> 24) & 0xff,
  (payload.length >> 16) & 0xff,
  (payload.length >> 8) & 0xff,
  payload.length & 0xff,
  ...payload,
];

void main() {
  final descriptors = fixture('check.desc');
  FlutwireProtobufDecoder reading(String type) => FlutwireProtobufDecoder(
    descriptorSet: descriptors,
    messageType: (call, {required isRequest}) => type,
  );
  final club = reading('check.v1.Club');

  test('every scalar type comes out as it went in', () {
    final text = decode(reading('check.v1.Scalars'), fixture('scalars.bin'))!;

    expect(
      text,
      '{\n'
      '  "d": 3.141592653589793,\n'
      '  "f": 0.1,\n'
      '  "i32": -2147483648,\n'
      '  "i64": -9223372036854775808,\n'
      '  "u32": 4294967295,\n'
      '  "u64": 18446744073709551615,\n'
      '  "s32": -1,\n'
      '  "s64": -9007199254740993,\n'
      '  "fx32": 4294967295,\n'
      '  "fx64": 18446744073709551615,\n'
      '  "sf32": -5,\n'
      '  "sf64": -6,\n'
      '  "b": true,\n'
      '  "s": "héllo ☃ \u{1F600}",\n'
      '  "raw": "01 02 ff"\n'
      '}',
    );
  });

  test('a message with every kind of field comes out whole', () {
    final text = decode(club, fixture('club.bin'))!;

    expect(
      text,
      '{\n'
      '  "name": "Hikers",\n'
      '  "level": "LEVEL_HIGH",\n'
      '  "tags": ["outdoor", "weekend"],\n'
      '  "scores": [3, 5, 8, -1],\n'
      '  "ratios": [0.5, 1.25],\n'
      '  "counts": {\n'
      '    "x": 1,\n'
      '    "y": 2\n'
      '  },\n'
      '  "members": {\n'
      '    "2": {\n'
      '      "handle": "bob"\n'
      '    },\n'
      '    "1": {\n'
      '      "handle": "ada",\n'
      '      "admin": true\n'
      '    }\n'
      '  },\n'
      '  "address": {\n'
      '    "city": "London",\n'
      '    "street": "St James\'s Square"\n'
      '  },\n'
      '  "branches": [\n'
      '    {\n'
      '      "city": "Bath"\n'
      '    },\n'
      '    {\n'
      '      "city": "Leeds"\n'
      '    }\n'
      '  ],\n'
      '  "email": "club@example.com",\n'
      '  "rank": 0,\n'
      '  "founded": "2023-11-14T22:13:20.500Z",\n'
      '  "season": "7776000.0015s",\n'
      '  "levels": ["LEVEL_LOW", "LEVEL_NEGATIVE", "LEVEL_HIGH"],\n'
      '  "kind": "KIND_TEAM",\n'
      '  "scalars": {\n'
      '    "i32": 7,\n'
      '    "s": "nested"\n'
      '  }\n'
      '}',
    );
  });

  test('an enum with a negative value is shown by name', () {
    // A negative enum is written as ten bytes, like a negative int32, and the
    // descriptor writes its number the same way.
    expect(decode(club, fixture('club.bin')), contains('"LEVEL_NEGATIVE"'));
  });

  test('a oneof shows the member that was set, and only that one', () {
    expect(
      decode(club, fixture('club_phone.bin')),
      '{\n  "name": "Phone",\n  "phone": 442079460000\n}',
    );
    expect(
      decode(club, fixture('club_office.bin')),
      '{\n  "name": "Office",\n  "office": {\n    "city": "Leeds"\n  }\n}',
    );
  });

  test('a field the schema does not have is shown by its number', () {
    expect(
      decode(club, fixture('club_unknown.bin')),
      '{\n  "name": "Hikers",\n  "<unknown 99>": 5\n}',
    );
  });

  test('a proto2 message reads a list written loose and one packed', () {
    expect(
      decode(reading('check.legacy.Old'), fixture('old.bin')),
      '{\n'
      '  "name": "Ada",\n'
      '  "loose": [1, 2, 3],\n'
      '  "tight": [4, 5, 6],\n'
      '  "blob": "00 01"\n'
      '}',
    );
  });

  group('over gRPC', () {
    // No message type is named: the method in the address says which it is.
    final grpc = FlutwireProtobufDecoder(descriptorSet: descriptors);

    test('a unary call finds the types of its method', () {
      expect(
        decode(
          grpc,
          frame(fixture('get_request.bin')),
          path: '/check.v1.Clubs/Get',
          type: 'application/grpc',
          isRequest: true,
        ),
        '{\n  "name": "Hikers"\n}',
      );
      expect(
        decode(
          grpc,
          frame(fixture('club_phone.bin')),
          path: '/check.v1.Clubs/Get',
          type: 'application/grpc',
        ),
        '{\n  "name": "Phone",\n  "phone": 442079460000\n}',
      );
    });

    test('a server stream lists its messages', () {
      final text = decode(
        grpc,
        [
          ...frame(fixture('club_phone.bin')),
          ...frame(fixture('club_office.bin')),
        ],
        path: '/check.v1.Clubs/List',
        type: 'application/grpc',
      )!;

      expect(text, contains('"name": "Phone"'));
      expect(text, contains('"name": "Office"'));
      expect(text, contains('"city": "Leeds"'));
    });
  });
}
