import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';

FlutwireBody body(String text, {String? type, int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(utf8.encode(text)),
  totalBytes: total,
  contentType: type,
);

void main() {
  group('kind from the media type', () {
    final cases = <String, FlutwireBodyKind>{
      'application/json': FlutwireBodyKind.json,
      'application/problem+json; charset=utf-8': FlutwireBodyKind.json,
      'text/json': FlutwireBodyKind.json,
      'application/xml': FlutwireBodyKind.xml,
      'application/atom+xml': FlutwireBodyKind.xml,
      'image/svg+xml': FlutwireBodyKind.xml,
      'text/html; charset=utf-8': FlutwireBodyKind.html,
      'application/x-www-form-urlencoded': FlutwireBodyKind.form,
      'multipart/form-data; boundary=abc': FlutwireBodyKind.multipart,
      'image/png': FlutwireBodyKind.image,
      'text/plain': FlutwireBodyKind.text,
      'text/csv': FlutwireBodyKind.text,
    };
    cases.forEach((type, kind) {
      test('$type is $kind', () {
        expect(body('x', type: type).kind, kind);
      });
    });
  });

  group('kind from the content when the media type says nothing', () {
    test('JSON object and array', () {
      expect(body('{"a":1}').kind, FlutwireBodyKind.json);
      expect(body('  [1,2]').kind, FlutwireBodyKind.json);
    });

    test('XML and HTML', () {
      expect(body('<?xml version="1.0"?><a/>').kind, FlutwireBodyKind.xml);
      expect(body('<a><b/></a>').kind, FlutwireBodyKind.xml);
      expect(body('<!DOCTYPE html><html></html>').kind, FlutwireBodyKind.html);
      expect(body('<HTML><body/></HTML>').kind, FlutwireBodyKind.html);
    });

    test('plain text', () {
      expect(body('hello world').kind, FlutwireBodyKind.text);
    });

    test('image magic numbers', () {
      final png = FlutwireBody(
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0]),
      );
      final jpeg = FlutwireBody(
        bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0]),
      );
      final webp = FlutwireBody(
        bytes: Uint8List.fromList([
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
      );
      expect(png.kind, FlutwireBodyKind.image);
      expect(jpeg.kind, FlutwireBodyKind.image);
      expect(webp.kind, FlutwireBodyKind.image);
    });

    test('compressed and unreadable bytes are binary', () {
      final gz = FlutwireBody(bytes: Uint8List.fromList([0x1F, 0x8B, 8, 0]));
      final noise = FlutwireBody(
        bytes: Uint8List.fromList(List.generate(200, (i) => 0x80 + i % 40)),
      );
      expect(gz.kind, FlutwireBodyKind.binary);
      expect(noise.kind, FlutwireBodyKind.binary);
      expect(gz.text, isNull);
    });

    test('a body cut inside a multi-byte character is still text', () {
      final bytes = utf8.encode('${'a' * 100}è');
      final cut = FlutwireBody(
        bytes: Uint8List.fromList(bytes.sublist(0, bytes.length - 1)),
        totalBytes: bytes.length,
      );
      expect(cut.kind, FlutwireBodyKind.text);
      expect(cut.truncated, isTrue);
    });

    test('nothing at all is empty', () {
      expect(FlutwireBody.empty().kind, FlutwireBodyKind.empty);
      expect(FlutwireBody.empty().isEmpty, isTrue);
      expect(FlutwireBody.empty().text, '');
    });
  });

  group('media type parameters', () {
    test('mime type is lower-cased and stripped of parameters', () {
      expect(
        body('x', type: 'Application/JSON; Charset=UTF-8').mimeType,
        'application/json',
      );
      expect(body('x').mimeType, isNull);
    });

    test('charset and boundary', () {
      final b = body(
        'x',
        type: 'multipart/form-data; boundary="xyz"; charset=UTF-8',
      );
      expect(b.charset, 'utf-8');
      expect(b.boundary, 'xyz');
    });
  });

  group('text', () {
    test('decodes UTF-8 by default', () {
      expect(body('caffè', type: 'text/plain').text, 'caffè');
    });

    test('honours a Latin-1 charset', () {
      final latin = FlutwireBody(
        bytes: Uint8List.fromList([0x63, 0x61, 0x66, 0x66, 0xE8]),
        contentType: 'text/plain; charset=iso-8859-1',
      );
      expect(latin.text, 'caffè');
    });

    test('is null for an unloaded body', () {
      final summary = FlutwireBody.unloaded(
        totalBytes: 10,
        contentType: 'application/json',
      );
      expect(summary.loaded, isFalse);
      expect(summary.text, isNull);
      expect(summary.truncated, isFalse);
      expect(summary.totalBytes, 10);
    });
  });

  group('truncation', () {
    test('a body shorter than its real size is truncated', () {
      final b = body('{"a":', type: 'application/json', total: 5000);
      expect(b.truncated, isTrue);
      expect(b.totalBytes, 5000);
    });

    test('a whole body is not', () {
      expect(body('{}').truncated, isFalse);
    });
  });

  group('JSON', () {
    test('parses a complete document', () {
      final b = body('{"a":[1,2]}', type: 'application/json');
      expect(b.isValidJson, isTrue);
      expect(b.jsonValue, {
        'a': [1, 2],
      });
      expect(b.prettyText, '{\n  "a": [\n    1,\n    2\n  ]\n}');
    });

    test('a literal null is valid JSON', () {
      final b = body('null', type: 'application/json');
      expect(b.isValidJson, isTrue);
      expect(b.jsonValue, isNull);
    });

    test('rejects a malformed document and shows it as it came', () {
      final b = body('{"a":', type: 'application/json');
      expect(b.isValidJson, isFalse);
      expect(b.prettyText, '{"a":');
    });

    test('never parses a cut body', () {
      final b = body('{"a":1}', type: 'application/json', total: 99);
      expect(b.isValidJson, isFalse);
    });
  });

  group('form bodies', () {
    test('decodes plus signs, escapes and repeats in order', () {
      final b = body(
        'q=hello+world&tag=a&tag=b%26c&empty=&flag',
        type: 'application/x-www-form-urlencoded',
      );
      expect(b.formFields.map((e) => '${e.key}=${e.value}'), [
        'q=hello world',
        'tag=a',
        'tag=b&c',
        'empty=',
        'flag=',
      ]);
    });

    test('keeps a value it cannot decode', () {
      expect(parseFormEncoded('a=%E0%A4%A').single.value, '%E0%A4%A');
    });
  });

  group('prettyXml', () {
    test('indents nested elements and keeps text on its line', () {
      expect(
        prettyXml('<a><b>text</b><c/></a>'),
        '<a>\n  <b>text</b>\n  <c/>\n</a>',
      );
    });

    test('leaves the declaration at the top', () {
      expect(
        prettyXml('<?xml version="1.0"?><a><b/></a>'),
        '<?xml version="1.0"?>\n<a>\n  <b/>\n</a>',
      );
    });

    test('survives a document that was cut short', () {
      expect(prettyXml('<a><b>te'), '<a>\n  <b>te');
    });
  });

  test('the description round-trips without the bytes', () {
    final b = body('{"a":1}', type: 'application/json');
    final back = FlutwireBody.fromJson(b.toJson());
    expect(back.totalBytes, b.totalBytes);
    expect(back.contentType, 'application/json');
    expect(back.loaded, isFalse);
    expect(back.withBytes(b.bytes).text, '{"a":1}');
  });
}
