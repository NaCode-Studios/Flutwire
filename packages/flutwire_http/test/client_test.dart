import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_http/flutwire_http.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

MockClient mock(StreamedResponse Function(BaseRequest, List<int>) reply) =>
    MockClient.streaming((request, body) async {
      final bytes = await body.expand((c) => c).toList();
      return reply(request, bytes);
    });

StreamedResponse ok(String body, {int status = 200}) => StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: {'content-type': 'application/json', 'set-cookie': 'sid=1'},
  reasonPhrase: 'OK',
);

List<FlutwireCall> recorded() {
  (Flutwire.store! as MemoryFlutwireStore).flush();
  return Flutwire.calls.value.reversed.toList();
}

Future<void> start({bool captureDartIo = false}) => Flutwire.init(
  config: FlutwireConfig(
    enabled: true,
    persist: false,
    captureDartIo: captureDartIo,
    notification: const FlutwireNotificationConfig(enabled: false),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Flutwire.reset();
  });

  test(
    'records the request and the whole response, and passes both on',
    () async {
      await start();
      final client = FlutwireClient(
        mock((r, b) => ok('{"id":7}', status: 201)),
      );
      final reply = await client.post(
        Uri.parse('https://api.test/items'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer s',
        },
        body: '{"name":"a"}',
      );
      expect(reply.statusCode, 201);
      expect(reply.body, '{"id":7}');

      final call = recorded().single;
      expect(call.source, FlutwireSource.http);
      expect(call.method, 'POST');
      expect(call.state, FlutwireCallState.completed);
      expect(call.statusCode, 201);
      expect(call.request.body.text, '{"name":"a"}');
      expect(call.request.headers.first('authorization'), '[redacted]');
      expect(call.response!.body.jsonValue, {'id': 7});
      expect(call.response!.headers.first('set-cookie'), '[redacted]');
    },
  );

  test(
    'a failure is a failed call and the error still reaches the app',
    () async {
      await start();
      final client = FlutwireClient(
        MockClient((r) async => throw const FormatException('boom')),
      );
      await expectLater(
        client.get(Uri.parse('https://api.test/')),
        throwsFormatException,
      );
      final call = recorded().single;
      expect(call.state, FlutwireCallState.failed);
      expect(call.error!.type, 'FormatException');
    },
  );

  test('reading only part of a response is a cancelled call', () async {
    await start();
    final client = FlutwireClient(
      mock(
        (r, b) => StreamedResponse(
          Stream.periodic(
            const Duration(milliseconds: 5),
            (i) => utf8.encode('chunk$i'),
          ),
          200,
        ),
      ),
    );
    final response = await client.send(
      Request('GET', Uri.parse('https://api.test/')),
    );
    final subscription = response.stream.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await subscription.cancel();
    expect(recorded().single.state, FlutwireCallState.cancelled);
  });

  test('describes a multipart request by its fields and files', () async {
    await start();
    final client = FlutwireClient(mock((r, b) => ok('{}')));
    final request = MultipartRequest('POST', Uri.parse('https://api.test/up'))
      ..fields['caption'] = 'hello'
      ..files.add(
        MultipartFile.fromBytes('file', [1, 2, 3], filename: 'a.bin'),
      );
    await client.send(request);
    final text = utf8.decode(recorded().single.request.body.bytes);
    expect(text, contains('caption = hello'));
    expect(text, contains('file = a.bin (3 bytes'));
  });

  group('next to the dart:io capture', () {
    test('stands down', () async {
      await start(captureDartIo: true);
      final client = FlutwireClient(mock((r, b) => ok('{}')));
      await client.get(Uri.parse('https://api.test/'));
      expect(recorded(), isEmpty);
    });

    test('records anyway when forced', () async {
      await start(captureDartIo: true);
      final client = FlutwireClient(mock((r, b) => ok('{}')), force: true);
      await client.get(Uri.parse('https://api.test/'));
      expect(recorded(), hasLength(1));
    });
  });

  test('does nothing when Flutwire is not running', () async {
    final client = FlutwireClient(mock((r, b) => ok('{"a":1}')));
    final reply = await client.get(Uri.parse('https://api.test/'));
    expect(reply.body, '{"a":1}');
    expect(Flutwire.calls.value, isEmpty);
  });
}
