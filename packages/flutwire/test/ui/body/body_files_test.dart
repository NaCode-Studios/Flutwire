import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/ui/body/body_files.dart';

import 'helpers.dart';

void main() {
  group('the extension that fits a body', () {
    test('follows what the body is', () {
      expect(bodyExtension(jsonBody('{}')), 'json');
      expect(bodyExtension(textBody('<a/>', type: 'application/xml')), 'xml');
      expect(bodyExtension(textBody('<p/>', type: 'text/html')), 'html');
      expect(bodyExtension(textBody('hi', type: 'text/plain')), 'txt');
      expect(
        bodyExtension(
          textBody('a=1', type: 'application/x-www-form-urlencoded'),
        ),
        'txt',
      );
      expect(bodyExtension(bytesBody([1, 2, 3])), 'bin');
      expect(bodyExtension(FlutwireBody.empty()), 'bin');
    });

    test('knows an SVG from other XML', () {
      expect(bodyExtension(textBody('<svg/>', type: 'image/svg+xml')), 'svg');
    });

    test('knows the common image formats', () {
      for (final (type, extension) in [
        ('image/png', 'png'),
        ('image/jpeg', 'jpg'),
        ('image/gif', 'gif'),
        ('image/webp', 'webp'),
        ('image/bmp', 'bmp'),
        ('image/tiff', 'img'),
      ]) {
        expect(
          bodyExtension(bytesBody(onePixelPng, type: type)),
          extension,
          reason: type,
        );
      }
    });
  });

  group('the name of a saved body', () {
    test('says which call and which side it came from', () {
      final call = testCall(id: 12);

      expect(
        bodyFileName(call, jsonBody('{}'), isRequest: true),
        'flutwire-12-request.json',
      );
      expect(
        bodyFileName(call, jsonBody('{}'), isRequest: false),
        'flutwire-12-response.json',
      );
    });

    test('takes the extension it is told to, for decoded text', () {
      expect(
        bodyFileName(
          testCall(id: 3),
          bytesBody([1, 2]),
          isRequest: false,
          extension: 'txt',
        ),
        'flutwire-3-response.txt',
      );
    });
  });
}
