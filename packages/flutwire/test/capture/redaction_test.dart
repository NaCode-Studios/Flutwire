import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/redaction.dart';
import 'package:flutwire/src/model/cookies.dart';
import 'package:flutwire/src/model/headers.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
String text(Uint8List b) => utf8.decode(b);

void main() {
  group('headers', () {
    test('the default policy hides credentials and nothing else', () {
      final out = const FlutwireRedaction().applyToHeaders(
        FlutwireHeaders.fromMap({
          'Authorization': 'Bearer abc',
          'Cookie': 'sid=1',
          'Set-Cookie': 'sid=2',
          'Accept': 'application/json',
        }),
      );
      expect(out.first('authorization'), '[redacted]');
      expect(out.first('cookie'), 'sid=[redacted]');
      expect(out.first('set-cookie'), 'sid=[redacted]');
      expect(out.first('accept'), 'application/json');
    });

    group('cookies', () {
      FlutwireHeaders hidden(Map<String, String> fields) =>
          const FlutwireRedaction().applyToHeaders(
            FlutwireHeaders.fromMap(fields),
          );

      test('keep their names and lose their values in a request', () {
        final out = hidden({'Cookie': 'session=abc123; theme=dark'});

        expect(out.first('cookie'), 'session=[redacted]; theme=[redacted]');
      });

      test(
        'keep their name and attributes and lose their value in a response',
        () {
          final out = hidden({
            'Set-Cookie':
                'session=abc123; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; '
                'HttpOnly; Secure; SameSite=Lax',
          });

          expect(
            out.first('set-cookie'),
            'session=[redacted]; Path=/; Expires=Wed, 21 Oct 2026 07:28:00 GMT; '
            'HttpOnly; Secure; SameSite=Lax',
          );
        },
      );

      test('are each hidden when the header repeats', () {
        final out = FlutwireRedaction().applyToHeaders(
          FlutwireHeaders([
            const MapEntry('Set-Cookie', 'a=1; Path=/'),
            const MapEntry('Set-Cookie', 'b=2; HttpOnly'),
          ]),
        );

        expect(out['set-cookie'], [
          'a=[redacted]; Path=/',
          'b=[redacted]; HttpOnly',
        ]);
      });

      test('are hidden as a whole when there is no name to keep', () {
        final out = hidden({
          'Cookie': 'abc123',
          'Set-Cookie': '=abc123; Path=/',
        });

        expect(out.first('cookie'), '[redacted]');
        expect(out.first('set-cookie'), '[redacted]');
      });

      test('use the mask the policy is given', () {
        final out = const FlutwireRedaction(
          mask: '***',
        ).applyToHeaders(FlutwireHeaders.fromMap({'Cookie': 'a=1'}));

        expect(out.first('cookie'), 'a=***');
      });

      test('stay as they are when the policy does not list them', () {
        final out = const FlutwireRedaction(
          headers: {'authorization'},
        ).applyToHeaders(FlutwireHeaders.fromMap({'Cookie': 'a=1'}));

        expect(out.first('cookie'), 'a=1');
      });

      test('are still listed by the cookie parsers afterwards', () {
        final out = hidden({
          'Cookie': 'session=abc123',
          'Set-Cookie': 'session=abc123; HttpOnly',
        });

        final sent = parseCookieHeader(out.first('cookie')!).single;
        final set = parseSetCookie(out.first('set-cookie')!)!;

        expect((sent.name, sent.value), ('session', '[redacted]'));
        expect(
          (set.name, set.value, set.httpOnly),
          ('session', '[redacted]', true),
        );
      });
    });

    test('none hides nothing', () {
      final headers = FlutwireHeaders.fromMap({'Authorization': 'Bearer abc'});
      expect(FlutwireRedaction.none.applyToHeaders(headers), headers);
    });

    test('a custom mask is used', () {
      final out = const FlutwireRedaction(
        headers: {'x-token'},
        mask: '***',
      ).applyToHeaders(FlutwireHeaders.fromMap({'X-Token': 't'}));
      expect(out.first('x-token'), '***');
    });
  });

  group('query parameters', () {
    const policy = FlutwireRedaction(queryParameters: {'token', 'api_key'});

    test('hides the listed values and keeps the rest', () {
      final out = policy.applyToUri(
        Uri.parse('https://x.test/a?q=1&Token=secret&api_key=k&q=2'),
      );
      expect(out.queryParameters['q'], '2');
      expect(out.query, contains('Token=%5Bredacted%5D'));
      expect(out.query, contains('api_key=%5Bredacted%5D'));
      expect(out.query, isNot(contains('secret')));
    });

    test('returns the same URI when nothing matches', () {
      final uri = Uri.parse('https://x.test/a?q=1');
      expect(identical(policy.applyToUri(uri), uri), isTrue);
    });
  });

  group('bodies', () {
    const policy = FlutwireRedaction(bodyFields: {'password', 'token'});

    test('hides JSON fields at any depth, whatever the value type', () {
      final out = policy.applyToBody(
        bytes(
          '{"user":"a","password":"hunter2","nested":{"token":123,"ok":true},'
          '"list":[{"Token":null}]}',
        ),
        contentType: 'application/json',
      );
      final s = text(out);
      expect(s, isNot(contains('hunter2')));
      expect(s, isNot(contains('123')));
      expect(s, contains('"user":"a"'));
      expect(s, contains('"password":"[redacted]"'));
      expect(s, contains('"token":"[redacted]"'));
      expect(s, contains('"Token":"[redacted]"'));
      expect(jsonDecode(s), isA<Map<String, Object?>>());
    });

    test('handles escaped quotes inside a value', () {
      final out = policy.applyToBody(
        bytes(r'{"password":"a\"b","x":1}'),
        contentType: 'application/json',
      );
      expect(text(out), '{"password":"[redacted]","x":1}');
    });

    test('works on a body that was cut before it became valid', () {
      final out = policy.applyToBody(
        bytes('{"password":"hunter2","rest":"abc'),
        contentType: 'application/json',
      );
      expect(text(out), isNot(contains('hunter2')));
    });

    test('hides form fields', () {
      final out = policy.applyToBody(
        bytes('user=a&password=hunter2&Token=t%26x'),
        contentType: 'application/x-www-form-urlencoded',
      );
      final s = text(out);
      expect(s, contains('user=a'));
      expect(s, isNot(contains('hunter2')));
      expect(s, isNot(contains('t%26x')));
    });

    test('leaves binary and unrelated bodies untouched', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      expect(
        identical(policy.applyToBody(png, contentType: 'image/png'), png),
        isTrue,
      );
      final clean = bytes('{"a":1}');
      expect(
        identical(
          policy.applyToBody(clean, contentType: 'application/json'),
          clean,
        ),
        isTrue,
      );
    });

    test('does nothing when no fields are configured', () {
      final b = bytes('{"password":"x"}');
      expect(
        identical(
          const FlutwireRedaction().applyToBody(
            b,
            contentType: 'application/json',
          ),
          b,
        ),
        isTrue,
      );
    });
  });
}
