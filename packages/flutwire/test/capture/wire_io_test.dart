// These tests talk to a real server on the loopback interface, through the
// clients people actually use. They deliberately avoid the widget test
// binding, which replaces every HttpClient with one that refuses to connect.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire_io.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/store/store.dart';
import 'package:http/http.dart' as http;

late HttpServer server;
late String base;

Future<void> handle(HttpRequest req) async {
  try {
    final path = req.uri.path;
    if (path == '/json') {
      req.response.headers
        ..contentType = ContentType.json
        ..set('content-encoding', 'gzip');
      req.response.add(
        gzip.encode(
          utf8.encode(
            jsonEncode({
              'ok': true,
              'items': [1, 2, 3],
            }),
          ),
        ),
      );
    } else if (path == '/echo') {
      final body = await utf8.decodeStream(req);
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({'echo': body, 'type': req.headers.contentType?.mimeType}),
      );
    } else if (path == '/redirect') {
      await req.response.redirect(Uri.parse('/json'));
      return;
    } else if (path.startsWith('/status/')) {
      req.response.statusCode = int.parse(path.substring(8));
      req.response.write('nope');
    } else if (path == '/big') {
      for (var i = 0; i < 100; i++) {
        req.response.add(List.filled(4096, 65));
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    } else if (path == '/ws') {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((m) => ws.add('echo:$m'));
      return;
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  } catch (_) {
    // The client walked away mid-body, which one of the tests does on purpose.
  }
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close(force: true));

  late MemoryFlutwireStore store;
  late FlutwireEngine engine;
  late void Function() uninstall;

  void start([FlutwireConfig config = const FlutwireConfig(enabled: true)]) {
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    engine = FlutwireEngine(config: config, store: store);
    uninstall = installWireCapture(engine);
  }

  tearDown(() {
    uninstall();
    HttpOverrides.global = null;
  });

  List<FlutwireCall> calls() => store.calls.value.reversed.toList();

  Future<List<FlutwireCall>> settled() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    store.flush();
    return calls();
  }

  test(
    'records a raw HttpClient call and hands the body on untouched',
    () async {
      start();
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$base/json?x=1'));
      request.headers.set('x-demo', 'raw');
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      client.close();

      expect(jsonDecode(text), {
        'ok': true,
        'items': [1, 2, 3],
      });
      final call = (await settled()).single;
      expect(call.method, 'GET');
      expect(call.uri.path, '/json');
      expect(call.uri.query, 'x=1');
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 200);
      expect(call.request.headers.first('x-demo'), 'raw');
      expect(call.response!.body.text, text);
      expect(call.response!.body.jsonValue, isA<Map<String, Object?>>());
      expect(call.response!.remoteAddress, '127.0.0.1');
      expect(call.response!.compression, 'gzip');
      expect(call.source, FlutwireSource.io);
      expect(call.timeToFirstByte, isNotNull);
    },
  );

  test('records package:http without the app wiring anything', () async {
    start();
    final client = http.Client();
    final reply = await client.post(
      Uri.parse('$base/echo'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'hello': 'world'}),
    );
    client.close();

    expect(reply.statusCode, 200);
    final call = (await settled()).single;
    expect(call.method, 'POST');
    expect(call.request.body.text, '{"hello":"world"}');
    expect(call.request.body.jsonValue, {'hello': 'world'});
    expect(call.response!.body.jsonValue, isA<Map<String, Object?>>());
  });

  test('records Dio, including a multipart upload', () async {
    start();
    final dio = Dio();
    await dio.get<dynamic>('$base/json');
    await dio.post<dynamic>('$base/echo', data: {'a': 1});
    await dio.post<dynamic>('$base/echo', data: FormData.fromMap({'f': 'v'}));
    dio.close();

    final seen = await settled();
    expect(seen, hasLength(3));
    expect(seen[1].request.body.text, '{"a":1}');
    final upload = seen[2].request.body;
    expect(upload.mimeType, 'multipart/form-data');
    expect(upload.boundary, isNotNull);
    expect(upload.totalBytes, greaterThan(50));
  });

  test('a followed redirect is one call that lists its hops', () async {
    start();
    final client = http.Client();
    final reply = await client.get(Uri.parse('$base/redirect'));
    client.close();

    expect(reply.statusCode, 200);
    final call = (await settled()).single;
    expect(call.statusCode, 200);
    expect(call.response!.redirects, hasLength(1));
    expect(call.response!.redirects.single.statusCode, 302);
    expect(call.response!.redirects.single.location.path, '/json');
  });

  test('an error status is a completed call, not a failed one', () async {
    start();
    final client = http.Client();
    await client.get(Uri.parse('$base/status/503'));
    client.close();
    final call = (await settled()).single;
    expect(call.state, FlutwireCallState.completed);
    expect(call.statusClass, FlutwireStatusClass.serverError);
    expect(call.isError, isTrue);
  });

  test('a refused connection is recorded as a failure', () async {
    start();
    final client = http.Client();
    await expectLater(
      client.get(Uri.parse('http://127.0.0.1:1/nope')),
      throwsA(isA<Exception>()),
    );
    client.close();
    final call = (await settled()).single;
    expect(call.state, FlutwireCallState.failed);
    expect(call.response, isNull);
    expect(call.error!.type, contains('Exception'));
  });

  test('a body the app stops reading is a cancelled call', () async {
    start();
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$base/big'));
    final response = await request.close();
    final subscription = response.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await subscription.cancel();
    client.close(force: true);

    final call = (await settled()).single;
    expect(call.state, FlutwireCallState.cancelled);
    expect(call.response!.body.totalBytes, greaterThan(0));
  });

  test(
    'keeps only the configured bytes of a big body, and the true size',
    () async {
      start(const FlutwireConfig(enabled: true, maxBodyBytes: 1000));
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$base/big'));
      final response = await request.close();
      var received = 0;
      await response.forEach((chunk) => received += chunk.length);
      client.close();

      expect(received, 100 * 4096);
      final body = (await settled()).single.response!.body;
      expect(body.bytes, hasLength(1000));
      expect(body.totalBytes, 100 * 4096);
      expect(body.truncated, isTrue);
    },
  );

  test('a WebSocket still works with the capture installed', () async {
    start();
    final socket = await WebSocket.connect('ws://127.0.0.1:${server.port}/ws');
    socket.add('ping');
    expect(await socket.first.timeout(const Duration(seconds: 2)), 'echo:ping');
    await socket.close();

    // Whether the handshake is routed through HttpClient depends on the
    // platform; where it is, it must be a finished protocol switch.
    for (final call in await settled()) {
      expect(call.statusCode, 101);
      expect(call.state, FlutwireCallState.completed);
    }
  });

  test('hides credentials before they are stored', () async {
    start();
    final client = http.Client();
    await client.get(
      Uri.parse('$base/json'),
      headers: {'authorization': 'Bearer secret', 'accept': 'application/json'},
    );
    client.close();
    final call = (await settled()).single;
    expect(call.request.headers.first('authorization'), '[redacted]');
    expect(call.request.headers.first('accept'), 'application/json');
  });

  test('an ignored call works and leaves no trace', () async {
    start(
      FlutwireConfig(
        enabled: true,
        ignore: [FlutwireIgnore.pathPrefix('/status')],
      ),
    );
    final client = http.Client();
    final reply = await client.get(Uri.parse('$base/status/418'));
    client.close();
    expect(reply.statusCode, 418);
    expect(reply.body, 'nope');
    expect(await settled(), isEmpty);
  });

  test('a paused engine records nothing but the traffic still flows', () async {
    start();
    engine.isPaused = true;
    final client = http.Client();
    final reply = await client.get(Uri.parse('$base/json'));
    client.close();
    expect(reply.statusCode, 200);
    expect(await settled(), isEmpty);
  });

  test('composes with overrides the app already installed', () async {
    var created = 0;
    HttpOverrides.global = _CountingOverrides(() => created++);
    start();
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$base/json'));
    await (await request.close()).drain<void>();
    client.close();
    expect(created, 1);
    expect(await settled(), hasLength(1));
  });

  test('installing twice records each call once', () async {
    start();
    installWireCapture(engine);
    final client = http.Client();
    await client.get(Uri.parse('$base/json'));
    client.close();
    expect(await settled(), hasLength(1));
  });

  test('closing the client cancels calls still waiting for a body', () async {
    start();
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$base/big'));
    await request.close();
    client.close(force: true);
    final call = (await settled()).single;
    expect(call.state, FlutwireCallState.cancelled);
  });
}

class _CountingOverrides extends HttpOverrides {
  _CountingOverrides(this.onCreate);

  final void Function() onCreate;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    onCreate();
    return super.createHttpClient(context);
  }
}
