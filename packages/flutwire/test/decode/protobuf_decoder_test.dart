import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';

import '../support/proto_encoder.dart';

FlutwireCall call({String path = '/items'}) => FlutwireCall(
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
  String? type = 'application/x-protobuf',
  String path = '/items',
  bool isRequest = false,
  int? total,
}) => decoder.decode(
  call(path: path),
  FlutwireBody(
    bytes: Uint8List.fromList(bytes),
    totalBytes: total,
    contentType: type,
  ),
  isRequest: isRequest,
);

Map<String, Object?> asMap(String? text) =>
    jsonDecode(text!) as Map<String, Object?>;

List<int> grpcFrame(List<int> payload, {int flag = 0}) => [
  flag,
  (payload.length >> 24) & 0xff,
  (payload.length >> 16) & 0xff,
  (payload.length >> 8) & 0xff,
  payload.length & 0xff,
  ...payload,
];

void main() {
  final descriptors = sampleDescriptorSet();
  final typed = FlutwireProtobufDecoder(
    descriptorSet: descriptors,
    messageType: (call, {required isRequest}) =>
        call.uri.path == '/people' ? 'demo.Person' : null,
  );
  const raw = FlutwireProtobufDecoder.raw();

  group('with a schema, a message', () {
    test('comes out by name, typed, in the order it was written', () {
      final text = decode(typed, samplePerson(), path: '/people');
      final person = asMap(text);

      expect(person.keys, [
        'name',
        'id',
        'emails',
        'address',
        'scores',
        'kind',
        'lucky',
        'delta',
        'ratio',
        'avatar',
        'active',
        'code',
        'previous',
        'joined',
        'big',
        'negative',
        'phone',
      ]);
      expect(person['name'], 'Ada Lovelace');
      expect(person['id'], 42);
      expect(person['emails'], ['ada@example.com', 'ada@analytical.engine']);
      expect(person['address'], {
        'city': 'London',
        'street': "St James's Square",
      });
      expect(person['scores'], {'math': 100, 'poetry': 97});
      expect(person['kind'], 'KIND_ADMIN');
      expect(person['lucky'], [3, 5, 8]);
      expect(person['delta'], -17);
      expect(person['ratio'], 0.5);
      expect(person['avatar'], '01 02 ff');
      expect(person['active'], true);
      expect(person['code'], 3735928559);
      expect(person['previous'], [
        {'city': 'Bath'},
        {'city': 'Leeds'},
      ]);
      expect(person['joined'], '2023-11-14T22:13:20.500Z');
      expect(person['negative'], -9007199254740993);
      expect(person['phone'], '+44 20 7946 0000');
    });

    test('keeps every digit of a 64 bit number', () {
      final text = decode(typed, samplePerson(), path: '/people')!;

      expect(text, contains('"big": 18446744073709551615'));
      expect(text, contains('"negative": -9007199254740993'));
    });

    test('reads a repeated number that was not packed as well', () {
      final bytes =
          (Wire()
                ..varint(7, 3)
                ..varint(7, 5)
                ..packed(7, [8, 13]))
              .build();

      expect(asMap(decode(typed, bytes, path: '/people'))['lucky'], [
        3,
        5,
        8,
        13,
      ]);
    });

    test('takes the last value of a field that is not repeated', () {
      final bytes =
          (Wire()
                ..varint(2, 1)
                ..varint(2, 2))
              .build();

      expect(asMap(decode(typed, bytes, path: '/people')), {'id': 2});
    });

    test('shows an enum value the schema does not name as its number', () {
      final bytes = (Wire()..varint(6, 9)).build();

      expect(asMap(decode(typed, bytes, path: '/people')), {'kind': 9});
    });

    test('reads a negative int32, which is written in ten bytes', () {
      final bytes = (Wire()..varint(2, -5)).build();

      expect(asMap(decode(typed, bytes, path: '/people')), {'id': -5});
    });

    test('writes a map entry whose key was left out as the empty key', () {
      final bytes = (Wire()..message(5, Wire()..varint(2, 5))).build();

      expect(asMap(decode(typed, bytes, path: '/people')), {
        'scores': {'': 5},
      });
    });

    test('shows a field the schema does not know by its number', () {
      final lite = FlutwireProtobufDecoder(
        descriptorSet: descriptors,
        messageType: (call, {required isRequest}) => 'demo.PersonLite',
      );

      final person = asMap(decode(lite, samplePerson()));

      expect(person['name'], 'Ada Lovelace');
      expect(person['id'], 42);
      expect(person['<unknown 3>'], [
        'ada@example.com',
        'ada@analytical.engine',
      ]);
      expect(person['<unknown 4>'], {'1': 'London', '2': "St James's Square"});
      expect(person['<unknown 6>'], 1);
    });

    test(
      'shows a field written in a wire type its declaration does not have',
      () {
        final bytes =
            (Wire()
                  ..varint(1, 7)
                  ..string(2, 'text'))
                .build();

        expect(asMap(decode(typed, bytes, path: '/people')), {
          'name': 7,
          'id': 'text',
        });
      },
    );

    test('writes a duration and a timestamp as one string each', () {
      final timing = FlutwireProtobufDecoder(
        descriptorSet: descriptors,
        messageType: (call, {required isRequest}) => 'demo.Timing',
      );

      String took(Wire duration) =>
          asMap(decode(timing, (Wire()..message(1, duration)).build()))['took']!
              as String;

      expect(
        took(
          Wire()
            ..varint(1, 90)
            ..varint(2, 500000000),
        ),
        '90.5s',
      );
      expect(took(Wire()..varint(1, 3)), '3s');
      expect(
        took(
          Wire()
            ..varint(1, -1)
            ..varint(2, -500000000),
        ),
        '-1.5s',
      );
      expect(took(Wire()..varint(2, 1000)), '0.000001s');
      expect(asMap(decode(timing, (Wire()..message(2, Wire())).build())), {
        'at': '1970-01-01T00:00:00.000Z',
      });
    });

    test('names the last value of an enum field that was written twice', () {
      final bytes =
          (Wire()
                ..varint(6, 1)
                ..varint(6, 2))
              .build();

      expect(asMap(decode(typed, bytes, path: '/people')), {
        'kind': 'KIND_GUEST',
      });
    });
  });

  group('with no schema, a message', () {
    test('comes out by field number', () {
      final bytes =
          (Wire()
                ..string(1, 'Ada')
                ..varint(2, 42)
                ..message(4, Wire()..string(1, 'London')))
              .build();

      expect(asMap(decode(raw, bytes)), {
        '1': 'Ada',
        '2': 42,
        '4': {'1': 'London'},
      });
    });

    test('lists a field that shows up more than once', () {
      final bytes =
          (Wire()
                ..varint(5, 1)
                ..varint(5, 2)
                ..varint(5, 3))
              .build();

      expect(asMap(decode(raw, bytes)), {
        '5': [1, 2, 3],
      });
    });

    test('shows a fixed width field as hex', () {
      final bytes =
          (Wire()
                ..fixed32(6, 1078530011)
                ..fixed64(7, BigInt.one))
              .build();

      expect(asMap(decode(raw, bytes)), {
        '6': '0x40490fdb',
        '7': '0x0000000000000001',
      });
    });

    test('shows bytes that are neither text nor a message as hex', () {
      final bytes = (Wire()..bytes(8, [0, 1, 255])).build();

      expect(asMap(decode(raw, bytes)), {'8': '00 01 ff'});
    });

    test('takes what reads as text for text, line breaks included', () {
      final bytes = (Wire()..string(9, 'line one\nline two')).build();

      expect(asMap(decode(raw, bytes)), {'9': 'line one\nline two'});
    });

    test(
      'takes what reads as a message for one, though a tag is a control character',
      () {
        final bytes =
            (Wire()..message(
                  4,
                  Wire()
                    ..varint(1, 1)
                    ..varint(2, 2),
                ))
                .build();

        expect(asMap(decode(raw, bytes)), {
          '4': {'1': 1, '2': 2},
        });
      },
    );

    test(
      'prefers a message to text that has a line break and parses as one',
      () {
        // 0a 0a is field 1, ten bytes long, and also a text of two line feeds.
        final bytes =
            (Wire()..bytes(3, [0x0a, 0x0a, ...utf8.encode('helloworld')]))
                .build();

        expect(asMap(decode(raw, bytes)), {
          '3': {'1': 'helloworld'},
        });
      },
    );

    test('prefers text to a message when it has no line break', () {
      // "hi" is also field 13 holding 105.
      final bytes = (Wire()..string(1, 'hi')).build();

      expect(asMap(decode(raw, bytes)), {'1': 'hi'});
    });

    test('shows an empty field as empty text', () {
      final bytes = (Wire()..bytes(1, const [])).build();

      expect(asMap(decode(raw, bytes)), {'1': ''});
    });

    test('shows a group as the fields inside it', () {
      final bytes = (Wire()..group(5, Wire()..varint(1, 7))).build();

      expect(asMap(decode(raw, bytes)), {
        '5': {'1': 7},
      });
    });
  });

  group('the media types it answers for', () {
    test('are the ones that say Protobuf', () {
      final bytes = (Wire()..varint(1, 1)).build();
      for (final type in [
        'application/x-protobuf',
        'application/protobuf',
        'application/vnd.google.protobuf',
        'application/x-google-protobuf',
        'application/x-protobuf; charset=binary',
      ]) {
        expect(decode(raw, bytes, type: type), isNotNull, reason: type);
      }
    });

    test('are not anything else', () {
      final bytes = (Wire()..varint(1, 1)).build();
      for (final type in [
        null,
        'application/json',
        'application/octet-stream',
        'application/grpc+json',
        'application/grpc-web-text',
      ]) {
        expect(decode(raw, bytes, type: type), isNull, reason: '$type');
      }
    });

    test('are named for whether there is a schema', () {
      expect(raw.name, 'Protobuf (no schema)');
      expect(typed.name, 'Protobuf');
    });
  });

  group('what it leaves alone', () {
    test('is a body that was cut', () {
      expect(decode(raw, samplePerson(), total: 5000), isNull);
    });

    test('is a body that is not a message', () {
      expect(decode(raw, [0x08]), isNull);
      expect(decode(raw, [0xff, 0xff]), isNull);
    });

    test('is an empty body', () {
      expect(decode(raw, []), isNull);
    });

    test('is a descriptor set that is not one', () {
      expect(
        () => FlutwireProtobufDecoder(descriptorSet: [0x0a, 0xff, 0x01]),
        throwsFormatException,
      );
    });
  });

  group('without a name for the message, a schema reads by number', () {
    test('when the callback has none', () {
      final bytes = (Wire()..string(1, 'Ada')).build();

      expect(asMap(decode(typed, bytes, path: '/other')), {'1': 'Ada'});
    });

    test('when there is no callback', () {
      final plain = FlutwireProtobufDecoder(descriptorSet: descriptors);
      final bytes = (Wire()..string(1, 'Ada')).build();

      expect(asMap(decode(plain, bytes)), {'1': 'Ada'});
    });

    test('when the callback names a message the schema does not have', () {
      final wrong = FlutwireProtobufDecoder(
        descriptorSet: descriptors,
        messageType: (call, {required isRequest}) => 'demo.Missing',
      );
      final bytes = (Wire()..string(1, 'Ada')).build();

      expect(asMap(decode(wrong, bytes)), {'1': 'Ada'});
    });

    test('and the callback is told which call and which side', () {
      FlutwireCall? seenCall;
      bool? seenSide;
      final spy = FlutwireProtobufDecoder(
        descriptorSet: descriptors,
        messageType: (call, {required isRequest}) {
          seenCall = call;
          seenSide = isRequest;
          return 'demo.FindRequest';
        },
      );

      final text = decode(
        spy,
        (Wire()..string(1, 'ada')).build(),
        path: '/find',
        isRequest: true,
      );

      expect(seenCall!.uri.path, '/find');
      expect(seenSide, isTrue);
      expect(asMap(text), {'query': 'ada'});
    });
  });

  group('gRPC', () {
    const find = '/demo.Directory/Find';
    final request = (Wire()..string(1, 'ada')).build();

    test('finds the types of a method from its address', () {
      final asked = decode(
        typed,
        grpcFrame(request),
        type: 'application/grpc',
        path: find,
        isRequest: true,
      );
      final answered = decode(
        typed,
        grpcFrame(samplePerson()),
        type: 'application/grpc',
        path: find,
      );

      expect(asMap(asked), {'query': 'ada'});
      expect(asMap(answered)['name'], 'Ada Lovelace');
      expect(asMap(answered)['kind'], 'KIND_ADMIN');
    });

    test('lists the messages of a stream, and the trailers after them', () {
      final trailers = utf8.encode('grpc-status: 0\r\ngrpc-message: OK\r\n');
      final body = [
        ...grpcFrame((Wire()..string(1, 'Ada')).build()),
        ...grpcFrame((Wire()..string(1, 'Grace')).build()),
        ...grpcFrame(trailers, flag: 0x80),
      ];

      final frames =
          jsonDecode(
                decode(
                  typed,
                  body,
                  type: 'application/grpc-web+proto',
                  path: find,
                )!,
              )
              as List<Object?>;

      expect(frames, [
        {'name': 'Ada'},
        {'name': 'Grace'},
        {
          'trailers': {'grpc-status': '0', 'grpc-message': 'OK'},
        },
      ]);
    });

    test('says so about a message that was compressed', () {
      final frames = asMap(
        decode(
          typed,
          grpcFrame([1, 2, 3], flag: 1),
          type: 'application/grpc',
          path: find,
        ),
      );

      expect(frames, {'compressed': true, 'bytes': '01 02 03'});
    });

    test('reads by number when the method is not in the schema', () {
      final text = decode(
        typed,
        grpcFrame(request),
        type: 'application/grpc',
        path: '/other.Service/Method',
        isRequest: true,
      );

      expect(asMap(text), {'1': 'ada'});
    });

    test('reads by number with no schema at all', () {
      final text = decode(
        raw,
        grpcFrame(request),
        type: 'application/grpc+proto',
        path: find,
        isRequest: true,
      );

      expect(asMap(text), {'1': 'ada'});
    });

    test('leaves alone a body whose frames are cut', () {
      expect(
        decode(raw, grpcFrame(request).sublist(0, 6), type: 'application/grpc'),
        isNull,
      );
      expect(decode(raw, [0, 0, 0], type: 'application/grpc'), isNull);
      expect(decode(raw, [0, 0, 0, 0, 9, 1], type: 'application/grpc'), isNull);
    });

    test('shows an empty message as an empty object', () {
      expect(decode(raw, grpcFrame(const []), type: 'application/grpc'), '{}');
    });
  });
}
