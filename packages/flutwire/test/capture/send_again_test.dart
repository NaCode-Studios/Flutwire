// These tests send real requests to a server on the loopback interface. They
// avoid the widget test binding, which replaces every HttpClient with one that
// refuses to connect.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/wire/send_again.dart';
import 'package:flutwire/src/capture/wire/wire_io.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/resend.dart';
import 'package:flutwire/src/store/store.dart';

late HttpServer server;
late String base;

Future<void> handle(HttpRequest req) async {
  try {
    final path = req.uri.path;
    if (path == '/echo') {
      final body = await utf8.decodeStream(req);
      final headers = <String, List<String>>{};
      req.headers.forEach((name, values) => headers[name] = values);
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'method': req.method,
          'uri': req.uri.toString(),
          'headers': headers,
          'body': body,
        }),
      );
    } else if (path == '/redirect') {
      await req.response.redirect(Uri.parse('/echo'));
      return;
    } else if (path == '/hang') {
      // Never answers. The test ends it.
      return;
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  } on Object {
    // The client walked away, which one of the tests does on purpose.
  }
}

/// App overrides that sit on top of whatever was installed before and chain to
/// it, the way a well behaved app's would.
class _Chaining extends HttpOverrides {
  _Chaining(this._previous);

  final HttpOverrides? _previous;
  int made = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    made++;
    final previous = _previous;
    return previous != null
        ? previous.createHttpClient(context)
        : super.createHttpClient(context);
  }
}

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close(force: true));

  late MemoryFlutwireStore store;
  late FlutwireEngine engine;

  void start([FlutwireConfig config = const FlutwireConfig(enabled: true)]) {
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    engine = FlutwireEngine(config: config, store: store);
  }

  tearDown(() async {
    HttpOverrides.global = null;
    await engine.dispose();
  });

  /// Waits until the call is over, however it ended.
  Future<FlutwireCall> settled(int id) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      final call = store.find(id);
      if (call != null && !call.isPending) return call;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('The call $id did not finish.');
  }

  FlutwireResend request(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Uint8List? body,
    int from = 7,
    String mask = '[redacted]',
  }) => FlutwireResend(
    from: from,
    method: method,
    uri: Uri.parse('$base$path'),
    headers: headers.entries,
    mask: mask,
    body: body,
  );

  Map<String, Object?> echoed(FlutwireCall call) =>
      jsonDecode(call.response!.body.text!) as Map<String, Object?>;

  group('sending a call again', () {
    test('records a call that names the one it repeats', () async {
      start();

      final id = await sendAgain(engine, request('/echo?a=1'));
      final call = await settled(id!);

      expect(call.resentFrom, 7);
      expect(call.method, 'GET');
      expect(call.uri.path, '/echo');
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 200);
      expect(echoed(call)['uri'], '/echo?a=1');
    });

    test(
      'sends the method, the header fields and the body it was given',
      () async {
        start();

        final id = await sendAgain(
          engine,
          request(
            '/echo',
            method: 'post',
            headers: {
              'Content-Type': 'application/json',
              'X-Trace': 'edited',
              // A length from before the body was edited.
              'Content-Length': '999',
            },
            body: bytes('{"qty":3}'),
          ),
        );
        final call = await settled(id!);

        final echo = echoed(call);
        expect(echo['method'], 'POST');
        expect(echo['body'], '{"qty":3}');
        final headers = echo['headers']! as Map<String, Object?>;
        expect(headers['x-trace'], ['edited']);
        expect(headers['content-type'], ['application/json']);
        expect(headers['content-length'], ['9']);
        expect(call.request.body.text, '{"qty":3}');
      },
    );

    test('sends a value only once, when the field is repeated', () async {
      start();

      final id = await sendAgain(
        engine,
        FlutwireResend(
          from: 1,
          method: 'GET',
          uri: Uri.parse('$base/echo'),
          headers: const [
            MapEntry('User-Agent', 'first'),
            MapEntry('X-Tag', 'a'),
            MapEntry('X-Tag', 'b'),
          ],
          mask: '[redacted]',
        ),
      );
      final call = await settled(id!);

      final headers = echoed(call)['headers']! as Map<String, Object?>;
      expect(headers['user-agent'], ['first']);
      expect(headers['x-tag'], ['a, b']);
    });

    test('leaves out what the redaction hid', () async {
      start();

      final id = await sendAgain(
        engine,
        request(
          '/echo',
          headers: {
            'Authorization': '[redacted]',
            'Cookie': 'session=[redacted]; theme=dark',
          },
        ),
      );
      final call = await settled(id!);

      final headers = echoed(call)['headers']! as Map<String, Object?>;
      expect(headers.containsKey('authorization'), isFalse);
      expect(headers['cookie'], ['theme=dark']);
    });

    test('sends a value that was typed over the mask', () async {
      start();

      final id = await sendAgain(
        engine,
        request('/echo', headers: {'Authorization': 'Bearer typed'}),
      );
      final call = await settled(id!);

      final headers = echoed(call)['headers']! as Map<String, Object?>;
      expect(headers['authorization'], ['Bearer typed']);
    });

    test('follows a redirect like the app would, and says so', () async {
      start();

      final id = await sendAgain(engine, request('/redirect'));
      final call = await settled(id!);

      expect(call.statusCode, 200);
      expect(call.response!.redirects, hasLength(1));
      expect(call.resentFrom, 7);
    });

    test('records a call that cannot connect as failed, with its id', () async {
      start();
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);

      final id = await sendAgain(
        engine,
        FlutwireResend(
          from: 7,
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:$port/'),
          headers: const [],
          mask: '[redacted]',
        ),
      );
      final call = await settled(id!);

      expect(call.state, FlutwireCallState.failed);
      expect(call.error!.type, 'SocketException');
      expect(call.resentFrom, 7);
    });

    test('ends a request nobody answers, as failed, at the deadline', () async {
      start();

      final id = await sendAgain(
        engine,
        request('/hang'),
        deadline: const Duration(milliseconds: 200),
      );
      final call = await settled(id!);

      expect(call.state, FlutwireCallState.failed);
      expect(call.error!.type, 'TimeoutException');
    });
  });

  group('the answer is wanted whatever else Flutwire is told', () {
    test('records while recording is paused', () async {
      start();
      engine.paused.value = true;

      final id = await sendAgain(engine, request('/echo'));

      expect((await settled(id!)).resentFrom, 7);
    });

    test('records a call to an ignored host', () async {
      start(
        FlutwireConfig(
          enabled: true,
          ignore: [FlutwireIgnore.host('127.0.0.1')],
        ),
      );

      final id = await sendAgain(engine, request('/echo'));

      expect((await settled(id!)).resentFrom, 7);
    });

    test('answers null when Flutwire does not record in this build', () async {
      start(const FlutwireConfig(enabled: false));

      final id = await sendAgain(engine, request('/echo'));

      expect(id, isNull);
      expect(store.calls.value, isEmpty);
    });
  });

  group('next to the capture', () {
    test('a resent call is recorded once', () async {
      start();
      installWireCapture(engine);

      final id = await sendAgain(engine, request('/echo'));
      await settled(id!);
      // Anything the capture recorded as well would be here by now.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(store.calls.value, hasLength(1));
      expect(store.calls.value.single.resentFrom, 7);
    });

    test('also when the app chained its own overrides on top', () async {
      start();
      installWireCapture(engine);
      final app = _Chaining(HttpOverrides.current);
      HttpOverrides.global = app;

      final id = await sendAgain(engine, request('/echo'));
      await settled(id!);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(app.made, greaterThan(0));
      expect(store.calls.value, hasLength(1));
      expect(store.calls.value.single.resentFrom, 7);
    });

    test('the app\'s own calls are still recorded after a resend', () async {
      start();
      installWireCapture(engine);
      await settled((await sendAgain(engine, request('/echo')))!);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('$base/echo'));
      await (await req.close()).drain<void>();
      client.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final calls = store.calls.value;
      expect(calls, hasLength(2));
      expect(calls.where((c) => c.resentFrom == null), hasLength(1));
    });
  });
}
