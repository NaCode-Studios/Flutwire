import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/multipart.dart';

FlutwireBody multipart(String raw, {int? total, String boundary = 'b'}) =>
    FlutwireBody(
      bytes: Uint8List.fromList(latin1.encode(raw)),
      totalBytes: total,
      contentType: 'multipart/form-data; boundary=$boundary',
    );

void main() {
  test('splits fields and files, keeping binary content intact', () {
    final png = String.fromCharCodes([0x89, 0x50, 0x4E, 0x47, 0, 255, 13, 10]);
    final raw = [
      '--b',
      'Content-Disposition: form-data; name="title"',
      '',
      'Hello world',
      '--b',
      'Content-Disposition: form-data; name="file"; filename="a b.png"',
      'Content-Type: image/png',
      '',
      png,
      '--b--',
      '',
    ].join('\r\n');
    final parts = parseMultipart(multipart(raw));
    expect(parts, hasLength(2));
    expect(parts[0].name, 'title');
    expect(parts[0].isFile, isFalse);
    expect(parts[0].text, 'Hello world');
    expect(parts[1].name, 'file');
    expect(parts[1].filename, 'a b.png');
    expect(parts[1].contentType, 'image/png');
    expect(parts[1].bytes, latin1.encode(png));
    expect(parts[1].text, isNull);
  });

  test('accepts bare line feeds', () {
    final raw = '--b\nContent-Disposition: form-data; name="x"\n\nv\n--b--\n';
    final parts = parseMultipart(multipart(raw));
    expect(parts.single.name, 'x');
    expect(parts.single.text, 'v');
  });

  test('returns the parts that arrived when the body was cut', () {
    final raw = [
      '--b',
      'Content-Disposition: form-data; name="a"',
      '',
      '1',
      '--b',
      'Content-Disposition: form-data; name="big"',
      '',
      'partial conte',
    ].join('\r\n');
    final parts = parseMultipart(multipart(raw, total: 9999));
    expect(parts.map((p) => p.name), ['a', 'big']);
    expect(parts.last.text, 'partial conte');
  });

  test('finds nothing without a boundary or without bytes', () {
    expect(
      parseMultipart(
        FlutwireBody(bytes: Uint8List(0), contentType: 'multipart/mixed'),
      ),
      isEmpty,
    );
    expect(
      parseMultipart(
        FlutwireBody(
          bytes: Uint8List.fromList([1, 2]),
          contentType: 'multipart/mixed',
        ),
      ),
      isEmpty,
    );
  });

  test('reads an unquoted name', () {
    final raw =
        '--b\r\nContent-Disposition: form-data; name=plain\r\n\r\nv\r\n--b--';
    expect(parseMultipart(multipart(raw)).single.name, 'plain');
  });
}
