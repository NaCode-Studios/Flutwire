import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/export/curl.dart';
import 'package:flutwire/src/export/export.dart';
import 'package:flutwire/src/export/har.dart';
import 'package:flutwire/src/export/text.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';

FlutwireBody body(String text, {String? type, int? total}) => FlutwireBody(
  bytes: Uint8List.fromList(utf8.encode(text)),
  totalBytes: total,
  contentType: type,
);

final started = DateTime.utc(2026, 10, 23, 12, 0, 0, 123);

FlutwireCall call({
  int id = 1,
  String method = 'GET',
  String url = 'https://api.test/items?id=1&tag=a%20b',
  Map<String, Object?> requestHeaders = const {},
  FlutwireBody? requestBody,
  int? status = 200,
  Map<String, Object?> responseHeaders = const {
    'content-type': 'application/json',
  },
  FlutwireBody? responseBody,
  FlutwireCallState state = FlutwireCallState.completed,
  FlutwireError? error,
  FlutwireGraphql? graphql,
  FlutwireSource source = FlutwireSource.io,
}) {
  return FlutwireCall(
    id: id,
    method: method,
    uri: Uri.parse(url),
    source: source,
    state: state,
    startedAt: started,
    firstByteAt: started.add(const Duration(milliseconds: 80)),
    endedAt: started.add(const Duration(milliseconds: 200)),
    request: FlutwireRequest(
      headers: FlutwireHeaders.fromMap(requestHeaders),
      body: requestBody ?? FlutwireBody.empty(),
    ),
    response: status == null
        ? null
        : FlutwireResponse(
            statusCode: status,
            headers: FlutwireHeaders.fromMap(responseHeaders),
            body: responseBody ?? body('{"ok":true}', type: 'application/json'),
            remoteAddress: '203.0.113.9',
            remotePort: 443,
          ),
    error: error,
    graphql: graphql,
  );
}

void main() {
  group('cURL', () {
    test('writes a plain GET on one line', () {
      expect(
        toCurl(call(), multiline: false),
        "curl 'https://api.test/items?id=1&tag=a%20b'",
      );
    });

    test('spreads a request with headers and a body over lines', () {
      final c = call(
        method: 'POST',
        requestHeaders: {
          'content-type': 'application/json',
          'Authorization': '[redacted]',
          'Content-Length': 7,
          'Host': 'api.test',
        },
        requestBody: body('{"a":1}', type: 'application/json'),
      );
      expect(
        toCurl(c),
        [
          "curl -X POST 'https://api.test/items?id=1&tag=a%20b' \\",
          "  -H 'content-type: application/json' \\",
          "  -H 'Authorization: [redacted]' \\",
          "  --data-raw '{\"a\":1}'",
        ].join('\n'),
      );
    });

    test('escapes single quotes in values', () {
      final c = call(
        method: 'POST',
        requestHeaders: {'x-note': "it's"},
        requestBody: body("a'b"),
      );
      final out = toCurl(c, multiline: false);
      expect(out, contains(r"-H 'x-note: it'\''s'"));
      expect(out, contains(r"--data-raw 'a'\''b'"));
    });

    test('uses --head for HEAD and adds --compressed for gzip', () {
      final c = call(
        method: 'HEAD',
        requestHeaders: {'accept-encoding': 'gzip'},
      );
      final out = toCurl(c, multiline: false);
      expect(out, startsWith('curl --head '));
      expect(out, endsWith('--compressed'));
      expect(out, isNot(contains('accept-encoding')));
    });

    test('says so when the body was cut or is binary', () {
      final cut = call(
        method: 'POST',
        requestBody: body('{"a":', type: 'application/json', total: 5000),
      );
      expect(toCurl(cut), startsWith('# The request body was cut'));
      final binary = call(
        method: 'POST',
        requestBody: FlutwireBody(
          bytes: Uint8List.fromList([0x1F, 0x8B, 8, 0]),
          contentType: 'application/octet-stream',
        ),
      );
      final out = toCurl(binary);
      expect(out, contains('is binary'));
      expect(out, isNot(contains('--data-raw')));
    });

    test('turns a multipart upload into -F fields', () {
      const boundary = 'xyz';
      final raw = [
        '--$boundary',
        'Content-Disposition: form-data; name="title"',
        '',
        'Hello',
        '--$boundary',
        'Content-Disposition: form-data; name="file"; filename="a.png"',
        'Content-Type: image/png',
        '',
        'PNGDATA',
        '--$boundary--',
        '',
      ].join('\r\n');
      final c = call(
        method: 'POST',
        requestHeaders: {'content-type': 'multipart/form-data; boundary=xyz'},
        requestBody: body(raw, type: 'multipart/form-data; boundary=xyz'),
      );
      final out = toCurl(c, multiline: false);
      expect(out, contains("-F 'title=Hello'"));
      expect(out, contains("-F 'file=@a.png'"));
      expect(out, isNot(contains('content-type')));
    });

    test('writes a callable function as the POST it is on the wire', () {
      final out = toCurl(
        call(
          method: 'CALL',
          source: FlutwireSource.functions,
          url: 'https://us-central1-demo.cloudfunctions.net/createClub',
          requestHeaders: {'content-type': 'application/json'},
          requestBody: body('{"data":{"a":1}}', type: 'application/json'),
        ),
        multiline: false,
      );
      expect(
        out,
        contains(
          "-X POST 'https://us-central1-demo.cloudfunctions.net/createClub'",
        ),
      );
      expect(out, contains('A callable function'));
      expect(out, isNot(contains('CALL')));
    });
  });

  group('HAR', () {
    final har = toHar([
      call(
        method: 'POST',
        requestHeaders: {
          'content-type': 'application/x-www-form-urlencoded',
          'cookie': 'sid=1; theme=dark',
        },
        requestBody: body(
          'a=1&b=two+words',
          type: 'application/x-www-form-urlencoded',
        ),
        responseHeaders: {
          'content-type': 'application/json',
          'set-cookie': 'sid=2; Path=/; HttpOnly; Secure',
          'location': '/next',
        },
        graphql: const FlutwireGraphql(operationName: 'Op'),
      ),
    ], version: '1.2.3');

    Map<String, Object?> entry() =>
        ((har['log']! as Map<String, Object?>)['entries']! as List<Object?>)
                .single!
            as Map<String, Object?>;

    test('is a HAR 1.2 document made by Flutwire', () {
      final log = har['log']! as Map<String, Object?>;
      expect(log['version'], '1.2');
      expect(log['creator'], {'name': 'Flutwire', 'version': '1.2.3'});
    });

    test('describes the request, with parsed query, params and cookies', () {
      final request = entry()['request']! as Map<String, Object?>;
      expect(request['method'], 'POST');
      expect(request['queryString'], [
        {'name': 'id', 'value': '1'},
        {'name': 'tag', 'value': 'a b'},
      ]);
      expect(request['cookies'], [
        {'name': 'sid', 'value': '1'},
        {'name': 'theme', 'value': 'dark'},
      ]);
      final post = request['postData']! as Map<String, Object?>;
      expect(post['params'], [
        {'name': 'a', 'value': '1'},
        {'name': 'b', 'value': 'two words'},
      ]);
    });

    test('writes a callable function with the method it travels with', () {
      final callable = toHar([
        call(method: 'CALL', source: FlutwireSource.functions),
      ]);
      final log = callable['log']! as Map<String, Object?>;
      final first =
          (log['entries']! as List<Object?>).single! as Map<String, Object?>;
      expect((first['request']! as Map<String, Object?>)['method'], 'POST');
    });

    test('describes the response, with cookie attributes and the redirect', () {
      final response = entry()['response']! as Map<String, Object?>;
      expect(response['status'], 200);
      expect(response['statusText'], 'OK');
      expect(response['redirectURL'], '/next');
      expect(response['cookies'], [
        {
          'name': 'sid',
          'value': '2',
          'path': '/',
          'httpOnly': true,
          'secure': true,
        },
      ]);
      final content = response['content']! as Map<String, Object?>;
      expect(content['text'], '{"ok":true}');
    });

    test('splits the time into wait and receive and keeps the server IP', () {
      final e = entry();
      expect(e['time'], 200);
      final timings = e['timings']! as Map<String, Object?>;
      expect(timings['wait'], 80);
      expect(timings['receive'], 120);
      expect(timings['dns'], -1);
      expect(e['serverIPAddress'], '203.0.113.9');
      expect(e['startedDateTime'], '2026-10-23T12:00:00.123Z');
    });

    test('writes a failed call with status 0 and the error', () {
      final failed = toHar([
        call(
          status: null,
          state: FlutwireCallState.failed,
          error: const FlutwireError(
            type: 'SocketException',
            message: 'refused',
          ),
        ),
      ]);
      final e =
          ((failed['log']! as Map<String, Object?>)['entries']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      expect((e['response']! as Map<String, Object?>)['status'], 0);
      expect(e['_error'], 'SocketException: refused');
    });

    test('puts a binary body in as base64', () {
      final image = toHar([
        call(
          responseBody: FlutwireBody(
            bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2]),
            contentType: 'image/png',
          ),
          responseHeaders: {'content-type': 'image/png'},
        ),
      ]);
      final e =
          ((image['log']! as Map<String, Object?>)['entries']! as List<Object?>)
                  .single!
              as Map<String, Object?>;
      final content =
          (e['response']! as Map<String, Object?>)['content']!
              as Map<String, Object?>;
      expect(content['encoding'], 'base64');
      expect(base64Decode(content['text']! as String), [
        0x89,
        0x50,
        0x4E,
        0x47,
        1,
        2,
      ]);
    });

    test('survives a JSON round trip', () {
      expect(jsonDecode(jsonEncode(har)), isA<Map<String, Object?>>());
    });
  });

  group('text', () {
    test('lays out the summary, headers and bodies', () {
      final out = callToText(
        call(
          method: 'POST',
          requestHeaders: {'content-type': 'application/json'},
          requestBody: body('{"a":1}', type: 'application/json'),
          graphql: const FlutwireGraphql(
            operationType: 'query',
            operationName: 'Feed',
          ),
        ),
      );
      expect(
        out,
        contains('URL:          https://api.test/items?id=1&tag=a%20b'),
      );
      expect(out, contains('Status:       200 OK'));
      expect(out, contains('Duration:     200 ms (first byte after 80 ms)'));
      expect(out, contains('Remote:       203.0.113.9:443'));
      expect(out, contains('GraphQL:      Feed'));
      expect(
        out,
        contains('--- Request headers ---\ncontent-type: application/json'),
      );
      expect(out, contains('--- Request body ---\n{\n  "a": 1\n}'));
      expect(out, contains('--- Response body ---\n{\n  "ok": true\n}'));
    });

    test('says what is missing instead of printing null', () {
      final out = callToText(
        call(
          status: null,
          state: FlutwireCallState.failed,
          error: const FlutwireError(
            type: 'SocketException',
            message: 'refused',
          ),
        ),
      );
      expect(out, contains('Status:       failed'));
      expect(out, contains('Error:        SocketException: refused'));
      expect(out, contains('--- Request body ---\n(empty)'));
      expect(out, isNot(contains('null')));
      expect(out, isNot(contains('--- Response')));
    });

    test('marks a cut body and describes a binary one', () {
      final cut = callToText(
        call(
          responseBody: body('{"a":', type: 'application/json', total: 9000),
        ),
      );
      expect(cut, contains('--- Content truncated: kept 5 B of 8.8 KB ---'));
      final binary = callToText(
        call(
          responseBody: FlutwireBody(
            bytes: Uint8List.fromList([0x1F, 0x8B, 8]),
            totalBytes: 2048,
            contentType: 'application/gzip',
          ),
        ),
      );
      expect(binary, contains('(binary data, 2.0 KB, application/gzip)'));
    });

    test('joins several calls oldest first', () {
      final out = callsToText([
        call(id: 2, url: 'https://api.test/second'),
        call(id: 1, url: 'https://api.test/first'),
      ], now: DateTime.utc(2026, 10, 23));
      expect(out, startsWith('Flutwire export: 2 calls, '));
      expect(out.indexOf('/first'), lessThan(out.indexOf('/second')));
      expect(out, contains('=================='));
    });
  });

  group('formats', () {
    final calls = [call(id: 2), call(id: 1)];

    test('each renders and has a file extension', () {
      for (final format in FlutwireExportFormat.values) {
        expect(format.render(calls), isNotEmpty, reason: format.name);
        expect(format.extension, isNotEmpty);
      }
    });

    test('JSON keeps the bodies', () {
      final decoded =
          jsonDecode(FlutwireExportFormat.json.render(calls))
              as Map<String, Object?>;
      final first =
          (decoded['calls']! as List<Object?>).first! as Map<String, Object?>;
      expect(first['id'], 1);
      final response = first['response']! as Map<String, Object?>;
      expect(
        (response['body']! as Map<String, Object?>)['text'],
        '{"ok":true}',
      );
    });
  });
}
