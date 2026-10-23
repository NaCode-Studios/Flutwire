// Like wire_io_test.dart, these tests talk to a real server on the loopback
// interface and stay off the widget test binding, which replaces every
// HttpClient with one that refuses to connect.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/wire/wire_io.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/engine.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/store/store.dart';

late HttpServer server;
late int port;

Future<void> handle(HttpRequest request) async {
  final response = request.response
    ..headers.set('x-test', 'yes')
    ..cookies.add(Cookie('session', 'abc'))
    ..write('ok');
  await response.close();
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen(handle);
  });

  tearDownAll(() => server.close(force: true));

  late HttpClient inner;
  late FlutwireHttpClient client;
  late MemoryFlutwireStore store;

  setUp(() {
    inner = HttpClient();
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    client = FlutwireHttpClient(
      inner,
      FlutwireEngine(config: const FlutwireConfig(enabled: true), store: store),
    );
  });

  tearDown(() => client.close(force: true));

  Future<List<FlutwireCall>> recorded() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    store.flush();
    return store.calls.value.reversed.toList();
  }

  group('the client hands its settings to the real one', () {
    test('and reads them back from it', () {
      client
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 7)
        ..maxConnectionsPerHost = 2
        ..userAgent = 'flutwire-test';

      expect(inner.autoUncompress, isFalse);
      expect(client.autoUncompress, isFalse);
      expect(inner.connectionTimeout, const Duration(seconds: 3));
      expect(client.connectionTimeout, const Duration(seconds: 3));
      expect(inner.idleTimeout, const Duration(seconds: 7));
      expect(client.idleTimeout, const Duration(seconds: 7));
      expect(inner.maxConnectionsPerHost, 2);
      expect(client.maxConnectionsPerHost, 2);
      expect(inner.userAgent, 'flutwire-test');
      expect(client.userAgent, 'flutwire-test');
    });

    test('including the ones that only have a setter', () async {
      // Separate statements: a cascade would read on into a closure's body.
      client.authenticate = (url, scheme, realm) async => true;
      client.authenticateProxy = (host, proxyPort, scheme, realm) async => true;
      client.badCertificateCallback = (certificate, host, certPort) => true;
      client.findProxy = (url) => 'DIRECT';
      client.keyLog = (line) {};
      client.addCredentials(
        Uri.parse('http://127.0.0.1:$port/'),
        'realm',
        HttpClientBasicCredentials('user', 'secret'),
      );
      client.addProxyCredentials(
        '127.0.0.1',
        port,
        'realm',
        HttpClientBasicCredentials('user', 'secret'),
      );

      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 200);
    });
  });

  group('every way of opening a request is recorded', () {
    test('by URL', () async {
      final url = Uri.parse('http://127.0.0.1:$port/by-url');
      for (final open in [
        client.getUrl,
        client.postUrl,
        client.putUrl,
        client.deleteUrl,
        client.patchUrl,
        client.headUrl,
        (Uri url) => client.openUrl('OPTIONS', url),
      ]) {
        await (await (await open(url)).close()).drain<void>();
      }

      final calls = await recorded();
      expect(calls.map((c) => c.method), [
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS',
      ]);
      expect(calls.every((c) => c.uri.path == '/by-url'), isTrue);
    });

    test('by host, port and path', () async {
      for (final open in [
        client.get,
        client.post,
        client.put,
        client.delete,
        client.patch,
        client.head,
        (String host, int port, String path) =>
            client.open('OPTIONS', host, port, path),
      ]) {
        await (await (await open(
          '127.0.0.1',
          port,
          '/by-host',
        )).close()).drain<void>();
      }

      final calls = await recorded();
      expect(calls.map((c) => c.method), [
        'GET',
        'POST',
        'PUT',
        'DELETE',
        'PATCH',
        'HEAD',
        'OPTIONS',
      ]);
      expect(calls.first.uri, Uri.parse('http://127.0.0.1:$port/by-host'));
    });

    test('with the query and the fragment taken off the path', () async {
      final request = await client.get('127.0.0.1', port, '/p?x=1&y=2#frag');
      await (await request.close()).drain<void>();

      final call = (await recorded()).single;
      expect(call.uri.path, '/p');
      expect(call.uri.query, 'x=1&y=2');
      expect(call.uri.hasFragment, isFalse);
    });
  });

  group('the request hands what it is given to the real one', () {
    test('settings, and what it reports about itself', () async {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/settings'),
      );
      request
        ..bufferOutput = false
        ..contentLength = 2
        ..followRedirects = false
        ..maxRedirects = 3
        ..persistentConnection = false;

      expect(request.bufferOutput, isFalse);
      expect(request.contentLength, 2);
      expect(request.encoding, latin1);
      expect(request.followRedirects, isFalse);
      expect(request.maxRedirects, 3);
      expect(request.persistentConnection, isFalse);
      expect(request.method, 'POST');
      expect(request.uri.path, '/settings');
      expect(request.headers, isNotNull);
      expect(request.cookies, isEmpty);
      expect(request.connectionInfo?.remotePort, port);

      request.write('ok');
      await (await request.close()).drain<void>();
    });

    test('and records every way of writing a body', () async {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/body'),
      );
      request.headers.contentType = ContentType.text;
      request
        ..add(utf8.encode('a'))
        ..write('b')
        ..writeAll(['c', 'd'], '-')
        ..writeCharCode(0x65)
        ..writeln('f');
      await request.addStream(Stream.value(utf8.encode('g')));
      await request.flush();
      await (await request.close()).drain<void>();

      final call = (await recorded()).single;
      expect(call.request.body.text, 'abc-def\ng');
    });

    test('a request that is aborted is a cancelled call', () async {
      // abort() is how a request that was never closed ends.
      // ignore: close_sinks
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/abort'),
      );
      request.abort();
      await request.done.then<void>((_) {}, onError: (Object _) {});

      final call = (await recorded()).single;
      expect(call.state, FlutwireCallState.cancelled);
    });
  });

  group('the response hands what it knows to the app', () {
    test('its status, headers and connection', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/response'),
      );
      final response = await request.close();
      final text = await utf8.decodeStream(response);

      expect(text, 'ok');
      expect(response.statusCode, 200);
      expect(response.reasonPhrase, 'OK');
      expect(response.headers.value('x-test'), 'yes');
      expect(response.cookies.single.name, 'session');
      expect(response.contentLength, isA<int>());
      expect(response.isRedirect, isFalse);
      expect(response.redirects, isEmpty);
      expect(response.certificate, isNull);
      expect(response.connectionInfo?.remotePort, port);
      expect(response.persistentConnection, isA<bool>());
      expect(
        response.compressionState,
        HttpClientResponseCompressionState.notCompressed,
      );
    });

    test('and the call it records says the same', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/response'),
      );
      await (await request.close()).drain<void>();

      final call = (await recorded()).single;
      expect(call.statusCode, 200);
      expect(call.response!.headers.first('x-test'), 'yes');
      expect(call.response!.remotePort, port);
    });
  });
}
