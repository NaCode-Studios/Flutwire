import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/decode/decoded_text.dart';

void main() {
  group('the text of a decoded value', () {
    test('writes the plain values the way JSON does', () {
      expect(renderDecoded(null), 'null');
      expect(renderDecoded(true), 'true');
      expect(renderDecoded(42), '42');
      expect(renderDecoded(-7), '-7');
      expect(renderDecoded(1.5), '1.5');
      expect(renderDecoded('a "quoted" line\n'), r'"a \"quoted\" line\n"');
    });

    test('writes a number too big for a double in full', () {
      expect(
        renderDecoded(BigInt.parse('18446744073709551615')),
        '18446744073709551615',
      );
    });

    test('writes the numbers JSON has no word for as strings', () {
      expect(renderDecoded(double.nan), '"NaN"');
      expect(renderDecoded(double.infinity), '"Infinity"');
      expect(renderDecoded(double.negativeInfinity), '"-Infinity"');
    });

    test('writes a moment as an ISO 8601 string in UTC', () {
      expect(
        renderDecoded(DateTime.utc(2023, 11, 14, 22, 13, 20, 500)),
        '"2023-11-14T22:13:20.500Z"',
      );
    });

    test('writes bytes as hex', () {
      expect(
        renderDecoded(DecodedBytes(Uint8List.fromList([0, 15, 255]))),
        '"00 0f ff"',
      );
    });

    test('says how many bytes there were when it does not write them all', () {
      final text = DecodedBytes(Uint8List(100)).toString();

      expect(text, endsWith('… (100 bytes)'));
      expect(text.split(' ').where((p) => p == '00'), hasLength(64));
    });

    test('keeps a short list of plain values on one line', () {
      expect(renderDecoded([1, 'two', null, true]), '[1, "two", null, true]');
      expect(renderDecoded(<Object?>[]), '[]');
    });

    test('puts a long list of plain values on a line each', () {
      final text = renderDecoded([
        for (var i = 0; i < 30; i++) 'item number $i',
      ]);

      expect(text.split('\n'), hasLength(32));
      expect(text, startsWith('[\n  "item number 0",\n'));
      expect(text, endsWith('"item number 29"\n]'));
    });

    test('puts a list that holds a list or a map on a line each', () {
      expect(
        renderDecoded([
          [1],
          {'a': 1},
        ]),
        '[\n  [1],\n  {\n    "a": 1\n  }\n]',
      );
    });

    test('indents a map and keeps the order of its keys', () {
      expect(
        renderDecoded({
          'b': 1,
          'a': {'c': <Object?>[], 'd': <String, Object?>{}},
        }),
        '{\n  "b": 1,\n  "a": {\n    "c": [],\n    "d": {}\n  }\n}',
      );
    });

    test('reads back as JSON when it holds only what JSON holds', () {
      final value = {
        'name': 'Ada',
        'tags': ['a', 'b'],
        'nested': {'n': 1.25, 'ok': false, 'nothing': null},
      };

      expect(jsonDecode(renderDecoded(value)), value);
    });

    test('writes anything it does not know as a string', () {
      expect(renderDecoded(const Duration(seconds: 3)), '"0:00:03.000000"');
    });

    test('stops following a value that nests deeper than is sane', () {
      Object? deep = 'bottom';
      for (var i = 0; i < 200; i++) {
        deep = [deep];
      }

      expect(renderDecoded(deep), contains('"…"'));
    });
  });
}
