import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/resend.dart';

FlutwireResend prepare(
  Map<String, String> headers, {
  String mask = '[redacted]',
  String method = 'GET',
  Uint8List? body,
}) => FlutwireResend(
  from: 1,
  method: method,
  uri: Uri.parse('https://api.test/items'),
  headers: headers.entries,
  mask: mask,
  body: body,
);

List<String> sent(FlutwireResend request) => [
  for (final field in request.headers.entries) '${field.key}: ${field.value}',
];

void main() {
  group('the header fields that are sent', () {
    test('keep their order and the case they were written in', () {
      final request = prepare({
        'Accept': 'application/json',
        'X-Trace': 'abc',
        'accept-language': 'it',
      });

      expect(sent(request), [
        'Accept: application/json',
        'X-Trace: abc',
        'accept-language: it',
      ]);
    });

    test('leave out the ones the client writes itself', () {
      final request = prepare({
        'Host': 'api.test',
        'Content-Length': '12',
        'Transfer-Encoding': 'chunked',
        'Connection': 'keep-alive',
        'Keep-Alive': 'timeout=5',
        'Accept': '*/*',
      });

      expect(sent(request), ['Accept: */*']);
      expect(request.hidden, isEmpty);
    });

    test('leave out a row with no name', () {
      final request = prepare({'  ': 'orphan', 'Accept': '*/*'});

      expect(sent(request), ['Accept: */*']);
    });
  });

  group('what the redaction hid', () {
    test('is not sent, and is named', () {
      final request = prepare({
        'Authorization': '[redacted]',
        'Proxy-Authorization': '[redacted]',
        'Accept': '*/*',
      });

      expect(sent(request), ['Accept: */*']);
      expect(request.hidden, ['Authorization', 'Proxy-Authorization']);
    });

    test('is sent once somebody types a value over it', () {
      final request = prepare({'Authorization': 'Bearer typed'});

      expect(sent(request), ['Authorization: Bearer typed']);
      expect(request.hidden, isEmpty);
    });

    test('follows the mask the app chose', () {
      final request = prepare({
        'Authorization': '***',
        'X-Other': '[redacted]',
      }, mask: '***');

      expect(sent(request), ['X-Other: [redacted]']);
      expect(request.hidden, ['Authorization']);
    });

    test('is nothing when the mask is empty', () {
      final request = prepare({'X-Empty': ''}, mask: '');

      expect(sent(request), ['X-Empty: ']);
      expect(request.hidden, isEmpty);
    });

    test('is dropped cookie by cookie, keeping the cookies that are real', () {
      final request = prepare({
        'Cookie': 'session=[redacted]; theme=dark; token=[redacted]',
      });

      expect(sent(request), ['Cookie: theme=dark']);
      expect(request.hidden, ['Cookie']);
    });

    test('leaves out a cookie header with nothing real in it', () {
      final request = prepare({'Cookie': 'a=[redacted]; b=[redacted]'});

      expect(sent(request), isEmpty);
      expect(request.hidden, ['Cookie']);
    });

    test('is dropped from a cookie piece that has no name', () {
      final request = prepare({'Cookie': '[redacted]; theme=dark'});

      expect(sent(request), ['Cookie: theme=dark']);
      expect(request.hidden, ['Cookie']);
    });

    test('is named once however many fields hold it', () {
      final request = prepare({'Cookie': 'a=[redacted]; b=[redacted]'});

      expect(request.hidden, hasLength(1));
    });

    test('keeps a real cookie header as it is', () {
      final request = prepare({'cookie': 'a=1; b=2'});

      expect(sent(request), ['cookie: a=1; b=2']);
      expect(request.hidden, isEmpty);
    });
  });

  group('isHiddenValue', () {
    test('matches a field by its whole value, whatever the name case', () {
      expect(
        isHiddenValue('Authorization', '[redacted]', '[redacted]'),
        isTrue,
      );
      expect(isHiddenValue('authorization', 'Bearer x', '[redacted]'), isFalse);
      expect(
        isHiddenValue('X-Note', 'it says [redacted] inside', '[redacted]'),
        isFalse,
      );
    });

    test('matches a cookie header when one of its cookies is hidden', () {
      expect(
        isHiddenValue('Cookie', 'a=[redacted]; b=2', '[redacted]'),
        isTrue,
      );
      expect(isHiddenValue('cookie', 'a=1; b=2', '[redacted]'), isFalse);
    });
  });

  group('the request', () {
    test('has its method in upper case', () {
      expect(prepare({}, method: ' patch ').method, 'PATCH');
    });

    test('sends no body for an empty one', () {
      expect(prepare({}, body: Uint8List(0)).body, isNull);
      expect(prepare({}).body, isNull);
    });

    test('keeps a body that has bytes', () {
      final body = Uint8List.fromList([1, 2, 3]);

      expect(prepare({}, body: body).body, body);
    });
  });
}
