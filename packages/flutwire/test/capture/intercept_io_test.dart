// These tests talk to a real server on the loopback interface, through the
// clients people actually use, as the other capture tests do: a rule has to
// work for what package:http and Dio really call, not for what a test imagines.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/redaction.dart';
import 'package:flutwire/src/capture/wire/wire_io.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/intercept/breakpoints.dart';
import 'package:flutwire/src/intercept/interception.dart';
import 'package:flutwire/src/intercept/rule.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/store/preferences.dart';
import 'package:flutwire/src/store/store.dart';
import 'package:http/http.dart' as http;

late HttpServer server;
late String base;

/// What reached the server, as it saw it.
final List<Map<String, Object?>> received = [];

Future<void> handle(HttpRequest req) async {
  final body = await utf8.decodeStream(req);
  received.add({
    'method': req.method,
    'target': req.uri.toString(),
    'demo': req.headers.value('x-demo'),
    'body': body,
  });
  req.response.headers.contentType = ContentType.json;
  req.response.write(
    jsonEncode({
      'method': req.method,
      'path': req.uri.path,
      'demo': req.headers.value('x-demo'),
      'body': body,
    }),
  );
  await req.response.close();
}

/// A client with nothing of Flutwire's underneath, as the inspector sends a call
/// again with.
HttpClient _unwrapped() {
  final client = HttpClient();
  return client is FlutwireHttpClient ? client.unwrapped : client;
}

/// Lets a held request go as it was held.
void _sendOn(FlutwireBreakpoints breakpoints, int id) =>
    breakpoints.resume(id, breakpoints.find(id)!);

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handle);
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDownAll(() => server.close(force: true));

  late MemoryFlutwireStore store;
  late FlutwireEngine engine;
  late FlutwireInterception interception;
  late void Function() uninstall;

  void start([
    FlutwireConfig config = const FlutwireConfig(
      enabled: true,
      interception: true,
    ),
  ]) {
    received.clear();
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    interception = FlutwireInterception(MemoryFlutwirePreferences());
    engine = FlutwireEngine(
      config: config,
      store: store,
      interception: interception,
    );
    uninstall = installWireCapture(engine);
  }

  tearDown(() {
    uninstall();
    HttpOverrides.global = null;
  });

  FlutwireRule mock(
    String pattern, {
    int status = 200,
    String body = '',
    Map<String, String> headers = const {},
    String? method,
    Duration delay = Duration.zero,
    bool enabled = true,
  }) {
    final rule = FlutwireRule(
      id: interception.rules.newId(),
      kind: FlutwireRuleKind.mock,
      pattern: pattern,
      method: method,
      enabled: enabled,
      response: FlutwireMockResponse(
        statusCode: status,
        headers: FlutwireHeaders.fromMap(headers),
        body: Uint8List.fromList(utf8.encode(body)),
        delay: delay,
      ),
    );
    interception.rules.add(rule);
    return rule;
  }

  FlutwireRule breakpoint(String pattern) {
    final rule = FlutwireRule(
      id: interception.rules.newId(),
      kind: FlutwireRuleKind.breakpoint,
      pattern: pattern,
    );
    interception.rules.add(rule);
    return rule;
  }

  List<FlutwireCall> calls() => store.calls.value.reversed.toList();

  Future<List<FlutwireCall>> settled() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    store.flush();
    return calls();
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: 'it did not come to pass in time');
  }

  /// A POST through a raw client, which waits for the answer in the
  /// background so that the test can look at what is held meanwhile.
  Future<String> post(
    HttpClient client,
    String path, {
    String body = 'hello',
    Map<String, String> headers = const {'x-demo': '1'},
  }) async {
    final request = await client.postUrl(Uri.parse('$base$path'));
    headers.forEach(request.headers.set);
    request.write(body);
    final response = await request.close();
    return utf8.decodeStream(response);
  }

  group('a mock', () {
    test('answers with the stored response and sends nothing', () async {
      start();
      mock(
        '127.0.0.1:*/echo',
        status: 201,
        body: '{"fake":true}',
        headers: {'content-type': 'application/json', 'x-fake': 'yes'},
      );
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      client.close();

      expect(response.statusCode, 201);
      expect(response.reasonPhrase, 'Created');
      expect(response.headers.value('x-fake'), 'yes');
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(response.contentLength, 13);
      expect(jsonDecode(text), {'fake': true});
      expect(received, isEmpty);
    });

    test('records the call, and marks it', () async {
      start();
      mock('127.0.0.1:*/echo', status: 201, body: '{"fake":true}');
      final client = HttpClient();

      await post(client, '/echo', body: '{"a":1}');
      final recorded = (await settled()).single;

      expect(recorded.source, FlutwireSource.io);
      expect(recorded.state, FlutwireCallState.completed);
      expect(recorded.intercept, FlutwireIntercept.mocked);
      expect(recorded.statusCode, 201);
      expect(recorded.request.body.text, '{"a":1}');
      expect(recorded.request.headers.first('x-demo'), '1');
      expect(recorded.request.headers.first('host'), startsWith('127.0.0.1:'));
      expect(recorded.response!.body.text, '{"fake":true}');
      expect(recorded.response!.headers.first('content-length'), '13');
    });

    test('answers even when the host cannot be reached', () async {
      start();
      mock('nowhere.invalid/*', body: 'still here');
      final client = HttpClient();

      final request = await client.getUrl(
        Uri.parse('https://nowhere.invalid/x'),
      );
      final response = await request.close();

      expect(await utf8.decodeStream(response), 'still here');
    });

    test('answers package:http', () async {
      start();
      mock(
        '127.0.0.1:*/echo',
        status: 202,
        body: 'for http',
        headers: {'content-type': 'text/plain', 'x-fake': 'yes'},
      );
      final client = http.Client();

      final response = await client.post(Uri.parse('$base/echo'), body: 'sent');
      client.close();

      expect(response.statusCode, 202);
      expect(response.body, 'for http');
      expect(response.headers['x-fake'], 'yes');
      expect(received, isEmpty);
    });

    test('answers Dio, which reads the response as it comes', () async {
      start();
      mock(
        '127.0.0.1:*/echo',
        body: '{"from":"dio"}',
        headers: {'content-type': 'application/json'},
      );
      final dio = Dio();

      final response = await dio.get<Object?>('$base/echo');

      expect(response.statusCode, 200);
      expect(response.data, {'from': 'dio'});
      expect(received, isEmpty);
    });

    test('tells a status of the server to Dio, as the server would', () async {
      start();
      mock('127.0.0.1:*/echo', status: 404, body: 'missing');
      final dio = Dio();

      await expectLater(
        dio.get<Object?>('$base/echo'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            404,
          ),
        ),
      );
    });

    test('hands on the cookies it sets', () async {
      start();
      mock(
        '127.0.0.1:*/echo',
        headers: {'set-cookie': 'session=abc; Path=/; HttpOnly'},
      );
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final response = await request.close();

      expect(response.cookies.single.name, 'session');
      expect(response.cookies.single.value, 'abc');
    });

    test(
      'does not serve what the server once said about the encoding',
      () async {
        start();
        mock(
          '127.0.0.1:*/echo',
          body: 'plain text',
          headers: {
            'content-encoding': 'gzip',
            'content-length': '999',
            'transfer-encoding': 'chunked',
            'x-kept': 'yes',
          },
        );
        final client = HttpClient();

        final request = await client.getUrl(Uri.parse('$base/echo'));
        final response = await request.close();

        expect(response.headers.value('content-encoding'), isNull);
        expect(response.headers.value('transfer-encoding'), isNull);
        expect(response.headers.value('x-kept'), 'yes');
        expect(response.contentLength, 10);
        expect(await utf8.decodeStream(response), 'plain text');
      },
    );

    test('waits for as long as the rule says', () async {
      start();
      mock('127.0.0.1:*/echo', delay: const Duration(milliseconds: 150));
      final client = HttpClient();
      final clock = Stopwatch()..start();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      await request.close();

      expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(140));
    });

    test('is not in force while the rule is off', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake', enabled: false);
      final client = HttpClient();

      final text = await post(client, '/echo');

      expect(jsonDecode(text), containsPair('body', 'hello'));
      expect(received, hasLength(1));
      expect((await settled()).single.intercept, isNull);
    });

    test('answers only the method it names', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake', method: 'POST');
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final text = await utf8.decodeStream(await request.close());

      expect(jsonDecode(text), containsPair('method', 'GET'));
      expect(received, hasLength(1));
    });

    test('is not applied to a call the inspector sends again', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = FlutwireHttpClient(_unwrapped(), engine, resentFrom: 1);

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final text = await utf8.decodeStream(await request.close());

      expect(jsonDecode(text), containsPair('method', 'GET'));
      expect(received, hasLength(1));
    });

    test('answers what is not recorded too', () async {
      start();
      engine.paused.value = true;
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final text = await utf8.decodeStream(await request.close());

      expect(text, 'fake');
      expect(await settled(), isEmpty);
    });

    test('fails the call when the app aborts the request', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      request.abort();

      await expectLater(request.close(), throwsA(isA<HttpException>()));
      expect((await settled()).single.state, FlutwireCallState.cancelled);
    });

    test('takes a second abort of the request as nothing', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      request
        ..abort()
        ..abort(StateError('again'));

      await expectLater(request.close(), throwsA(isA<HttpException>()));
      expect((await settled()).single.state, FlutwireCallState.cancelled);
    });

    test('writes text to the request the way a request does', () async {
      start();
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = HttpClient();

      final request = await client.postUrl(Uri.parse('$base/echo'));
      request
        ..write('a')
        ..writeAll([1, 2], ',')
        ..writeCharCode(0x21)
        ..writeln('!');
      await utf8.decodeStream(await request.close());

      final call = (await settled()).single;
      expect(utf8.decode(call.request.body.bytes), 'a1,2!!\n');
    });

    test('answers once the interception is off for the app', () async {
      start(const FlutwireConfig(enabled: true));
      engine = FlutwireEngine(
        config: const FlutwireConfig(enabled: true),
        store: store,
      );
      uninstall();
      uninstall = installWireCapture(engine);
      final client = HttpClient();

      final text = await post(client, '/echo');

      // An engine with no interception reads traffic and changes none.
      expect(jsonDecode(text), containsPair('body', 'hello'));
    });
  });

  group('a breakpoint', () {
    test('holds the request, then sends it as it was', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      await until(() => interception.breakpoints.held.isNotEmpty);

      // The app is waiting and nothing has left.
      expect(received, isEmpty);
      final held = interception.breakpoints.held.single;
      expect(held.method, 'POST');
      expect(held.uri.path, '/echo');
      expect(utf8.decode(held.body), 'hello');
      expect(held.headers.first('x-demo'), '1');
      expect(held.headers.first('host'), startsWith('127.0.0.1:'));

      _sendOn(interception.breakpoints, held.id);
      final text = await answer;

      expect(jsonDecode(text), containsPair('body', 'hello'));
      expect(received, hasLength(1));
      final recorded = await settled();
      expect(recorded, hasLength(1));
      expect(recorded.single.state, FlutwireCallState.completed);
      // It was held, even though it went as it was, and the list says so.
      expect(recorded.single.intercept, FlutwireIntercept.held);
      expect(recorded.single.request.body.text, 'hello');
      expect(recorded.single.response!.body.text, contains('"hello"'));
    });

    test('sends it with the changes, and records both calls', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      await until(() => interception.breakpoints.held.isNotEmpty);
      final held = interception.breakpoints.held.single;
      interception.breakpoints.resume(
        held.id,
        held.copyWith(
          method: 'PUT',
          uri: Uri.parse('$base/echo?changed=1'),
          headers: FlutwireHeaders.fromMap({'x-demo': '2'}),
          body: Uint8List.fromList(utf8.encode('changed')),
        ),
      );
      final text = await answer;

      expect(jsonDecode(text), {
        'method': 'PUT',
        'path': '/echo',
        'demo': '2',
        'body': 'changed',
      });
      expect(received.single['method'], 'PUT');
      expect(received.single['target'], '/echo?changed=1');
      final recorded = await settled();
      expect(recorded, hasLength(2));
      final original = recorded.first;
      final edited = recorded.last;
      expect(original.method, 'POST');
      expect(original.request.body.text, 'hello');
      expect(original.state, FlutwireCallState.cancelled);
      expect(original.intercept, FlutwireIntercept.held);
      expect(original.error!.type, 'Breakpoint');
      expect(edited.method, 'PUT');
      expect(edited.uri.query, 'changed=1');
      expect(edited.request.body.text, 'changed');
      expect(edited.request.headers.first('x-demo'), '2');
      expect(edited.intercept, FlutwireIntercept.edited);
      expect(edited.resentFrom, original.id);
      expect(edited.state, FlutwireCallState.completed);
      expect(edited.response!.body.text, contains('"changed"'));
    });

    test('lets the app go on when a header is only taken away', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      await until(() => interception.breakpoints.held.isNotEmpty);
      final held = interception.breakpoints.held.single;
      interception.breakpoints.resume(
        held.id,
        held.copyWith(headers: FlutwireHeaders.empty),
      );
      final text = await answer;

      expect(jsonDecode(text), containsPair('demo', null));
      expect(received.single['demo'], isNull);
    });

    test('stops the request, and the app is told it failed', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      final failure = expectLater(answer, throwsA(isA<HttpException>()));
      await until(() => interception.breakpoints.held.isNotEmpty);
      interception.breakpoints.stop(interception.breakpoints.held.single.id);
      await failure;

      expect(received, isEmpty);
      final recorded = (await settled()).single;
      expect(recorded.state, FlutwireCallState.failed);
      expect(recorded.intercept, FlutwireIntercept.held);
      expect(recorded.error!.message, 'Stopped at a breakpoint.');
    });

    test('holds a request that has no body', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final text = () async {
        final request = await client.getUrl(Uri.parse('$base/echo'));
        return utf8.decodeStream(await request.close());
      }();
      await until(() => interception.breakpoints.held.isNotEmpty);
      expect(interception.breakpoints.held.single.body, isEmpty);
      _sendOn(
        interception.breakpoints,
        interception.breakpoints.held.single.id,
      );

      expect(jsonDecode(await text), containsPair('method', 'GET'));
    });

    test('holds the request as it really is, and records it hidden', () async {
      start(
        const FlutwireConfig(
          enabled: true,
          interception: true,
          redaction: FlutwireRedaction(bodyFields: {'password'}),
        ),
      );
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(
        client,
        '/echo',
        body: '{"password":"hunter2"}',
        headers: {'authorization': 'Bearer secret', 'x-demo': '1'},
      );
      await until(() => interception.breakpoints.held.isNotEmpty);
      final held = interception.breakpoints.held.single;

      // Whoever holds the request sees what it says, secrets included.
      expect(held.headers.first('authorization'), 'Bearer secret');
      expect(utf8.decode(held.body), contains('hunter2'));
      _sendOn(interception.breakpoints, held.id);
      await answer;

      // The record of it hides them.
      final recorded = (await settled()).single;
      expect(recorded.request.headers.first('authorization'), '[redacted]');
      expect(recorded.request.body.text, isNot(contains('hunter2')));
      // What went out was the real thing.
      expect(received.single['body'], contains('hunter2'));
    });

    test(
      'hides in the record of the changed call what the policy hides',
      () async {
        start();
        breakpoint('127.0.0.1:*/echo');
        final client = HttpClient();

        final answer = post(client, '/echo');
        await until(() => interception.breakpoints.held.isNotEmpty);
        final held = interception.breakpoints.held.single;
        interception.breakpoints.resume(
          held.id,
          held.copyWith(
            headers: FlutwireHeaders.fromMap({
              'authorization': 'Bearer changed',
              'x-demo': '2',
            }),
          ),
        );
        await answer;

        final edited = (await settled()).last;
        expect(edited.request.headers.first('authorization'), '[redacted]');
        expect(edited.request.headers.first('x-demo'), '2');
      },
    );

    test('holds whatever client the app uses', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = http.Client();

      final answer = client.post(Uri.parse('$base/echo'), body: 'from http');
      await until(() => interception.breakpoints.held.isNotEmpty);
      _sendOn(
        interception.breakpoints,
        interception.breakpoints.held.single.id,
      );
      final response = await answer;
      client.close();

      expect(jsonDecode(response.body), containsPair('body', 'from http'));
    });

    test('holds Dio too, and sends what was changed', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final dio = Dio();

      final answer = dio.post<Object?>('$base/echo', data: 'from dio');
      await until(() => interception.breakpoints.held.isNotEmpty);
      final held = interception.breakpoints.held.single;
      interception.breakpoints.resume(
        held.id,
        held.copyWith(body: Uint8List.fromList(utf8.encode('changed'))),
      );
      final response = await answer;

      expect(response.data, containsPair('body', 'changed'));
    });

    test('holds several requests, each on its own', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final first = post(client, '/echo', body: 'first');
      final second = post(client, '/echo', body: 'second');
      await until(() => interception.breakpoints.held.length == 2);
      final held = interception.breakpoints.held;
      final secondId = held.firstWhere((r) => utf8.decode(r.body) == 'second');
      final firstId = held.firstWhere((r) => utf8.decode(r.body) == 'first');

      _sendOn(interception.breakpoints, secondId.id);
      expect(jsonDecode(await second), containsPair('body', 'second'));
      expect(interception.breakpoints.held.single.id, firstId.id);
      _sendOn(interception.breakpoints, firstId.id);
      expect(jsonDecode(await first), containsPair('body', 'first'));
    });

    test('is not applied to a call the inspector sends again', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = FlutwireHttpClient(_unwrapped(), engine, resentFrom: 1);

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final text = await utf8.decodeStream(await request.close());

      expect(jsonDecode(text), containsPair('method', 'GET'));
      expect(interception.breakpoints.held, isEmpty);
    });

    test('holds what is not recorded too', () async {
      start();
      engine.paused.value = true;
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      await until(() => interception.breakpoints.held.isNotEmpty);
      _sendOn(
        interception.breakpoints,
        interception.breakpoints.held.single.id,
      );

      expect(jsonDecode(await answer), containsPair('body', 'hello'));
      expect(await settled(), isEmpty);
    });

    test('lets a mock answer first, so that nothing is held', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      mock('127.0.0.1:*/echo', body: 'fake');
      final client = HttpClient();

      final request = await client.getUrl(Uri.parse('$base/echo'));
      final text = await utf8.decodeStream(await request.close());

      expect(text, 'fake');
      expect(interception.breakpoints.held, isEmpty);
    });

    test(
      'is stopped when the client that made the request is shut down',
      () async {
        start();
        breakpoint('127.0.0.1:*/echo');
        final client = HttpClient();

        final answer = post(client, '/echo');
        final failure = expectLater(answer, throwsA(isA<HttpException>()));
        await until(() => interception.breakpoints.held.isNotEmpty);
        client.close(force: true);
        await failure;

        expect(interception.breakpoints.held, isEmpty);
        expect(received, isEmpty);
      },
    );

    test('is released when the app aborts the request it holds', () async {
      start();
      breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final request = await client.postUrl(Uri.parse('$base/echo'));
      request.write('hello');
      final closing = request.close();
      final failure = expectLater(closing, throwsA(isA<HttpException>()));
      await until(() => interception.breakpoints.held.isNotEmpty);
      request.abort();
      await failure;

      expect(interception.breakpoints.held, isEmpty);
      expect(received, isEmpty);
    });

    test(
      'is stopped when Flutwire is turned off, so that no call is left waiting',
      () async {
        start();
        breakpoint('127.0.0.1:*/echo');
        final client = HttpClient();

        final answer = post(client, '/echo');
        final failure = expectLater(answer, throwsA(isA<HttpException>()));
        await until(() => interception.breakpoints.held.isNotEmpty);
        await engine.dispose();
        await failure;

        expect(received, isEmpty);
      },
    );

    test('is not in force while the rule is off', () async {
      start();
      final rule = breakpoint('127.0.0.1:*/echo');
      interception.rules.setEnabled(rule.id, enabled: false);
      final client = HttpClient();

      final text = await post(client, '/echo');

      expect(jsonDecode(text), containsPair('body', 'hello'));
      expect(interception.breakpoints.held, isEmpty);
    });

    test('leaves a request that does not match alone', () async {
      start();
      breakpoint('127.0.0.1:*/other');
      final client = HttpClient();

      final text = await post(client, '/echo');

      expect(jsonDecode(text), containsPair('body', 'hello'));
    });

    test(
      'sends what is let go to another host, when the address was changed',
      () async {
        start();
        breakpoint('127.0.0.1:*/echo');
        final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => other.close(force: true));
        final reached = <String>[];
        other.listen((req) async {
          reached.add(req.uri.path);
          req.response.write('from the other server');
          await req.response.close();
        });
        final client = HttpClient();

        final answer = post(client, '/echo');
        await until(() => interception.breakpoints.held.isNotEmpty);
        final held = interception.breakpoints.held.single;
        interception.breakpoints.resume(
          held.id,
          held.copyWith(uri: Uri.parse('http://127.0.0.1:${other.port}/moved')),
        );

        expect(await answer, 'from the other server');
        expect(reached, ['/moved']);
        expect(received, isEmpty);
      },
    );

    test('says which breakpoint holds a request', () async {
      start();
      final rule = breakpoint('127.0.0.1:*/echo');
      final client = HttpClient();

      final answer = post(client, '/echo');
      await until(() => interception.breakpoints.held.isNotEmpty);

      expect(interception.breakpoints.held.single.ruleId, rule.id);
      interception.breakpoints.stopAll();
      await answer.then<void>((_) {}, onError: (Object _) {});
    });

    test(
      'goes on as it was when the breakpoint that holds it is off',
      () async {
        start();
        final rule = breakpoint('127.0.0.1:*/echo');
        final client = HttpClient();

        final answer = post(client, '/echo');
        await until(() => interception.breakpoints.held.isNotEmpty);
        interception.rules.setEnabled(rule.id, enabled: false);

        expect(jsonDecode(await answer), containsPair('body', 'hello'));
        expect(received, hasLength(1));
        expect(interception.breakpoints.held, isEmpty);
      },
    );
  });

  test('a breakpoint hold is a typed ticket', () {
    expect(
      FlutwireBreakpoints().hold(
        method: 'GET',
        uri: Uri.parse('https://a.test/'),
        headers: FlutwireHeaders.empty,
        body: Uint8List(0),
      ),
      isA<FlutwireHoldTicket>(),
    );
  });
}
