import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_dio/flutwire_dio.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    'set-cookie': ['sid=1; Path=/'],
  },
);

Dio dioWith(
  Future<ResponseBody> Function(RequestOptions) handler, {
  bool force = false,
}) {
  final dio = Dio()
    ..httpClientAdapter = FakeAdapter(handler)
    ..interceptors.add(FlutwireDioInterceptor(force: force));
  return dio;
}

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

  test('records a JSON call with what Dio sent and what it got', () async {
    await start();
    final dio = dioWith((o) async => json({'id': 7}, status: 201));
    final reply = await dio.post<Object?>(
      'https://api.test/items?x=1',
      data: {'name': 'a'},
      options: Options(headers: {'Authorization': 'Bearer secret'}),
    );
    expect(reply.statusCode, 201);

    final call = recorded().single;
    expect(call.source, FlutwireSource.dio);
    expect(call.method, 'POST');
    expect(call.uri.toString(), 'https://api.test/items?x=1');
    expect(call.state, FlutwireCallState.completed);
    expect(call.statusCode, 201);
    expect(call.request.headers.first('authorization'), '[redacted]');
    expect(call.request.headers.contentType, startsWith('application/json'));
    expect(call.request.body.text, '{"name":"a"}');
    expect(call.response!.body.jsonValue, {'id': 7});
    expect(call.response!.headers.first('set-cookie'), '[redacted]');
  });

  test('an error status is a completed call with its body', () async {
    await start();
    final dio = dioWith((o) async => json({'error': 'nope'}, status: 404));
    await expectLater(
      dio.get<Object?>('https://api.test/missing'),
      throwsA(isA<DioException>()),
    );
    final call = recorded().single;
    expect(call.state, FlutwireCallState.completed);
    expect(call.statusCode, 404);
    expect(call.response!.body.text, '{"error":"nope"}');
    expect(call.isError, isTrue);
  });

  test('a connection error is a failed call', () async {
    await start();
    final dio = dioWith(
      (o) async => throw DioException.connectionError(
        requestOptions: o,
        reason: 'no route to host',
      ),
    );
    await expectLater(
      dio.get<Object?>('https://api.test/'),
      throwsA(isA<DioException>()),
    );
    final call = recorded().single;
    expect(call.state, FlutwireCallState.failed);
    expect(call.response, isNull);
    expect(call.error, isNotNull);
  });

  test('a cancelled request is a cancelled call', () async {
    await start();
    final token = CancelToken();
    final dio = dioWith((o) async {
      token.cancel();
      throw DioException.requestCancelled(requestOptions: o, reason: 'stop');
    });
    await expectLater(
      dio.get<Object?>('https://api.test/', cancelToken: token),
      throwsA(isA<DioException>()),
    );
    expect(recorded().single.state, FlutwireCallState.cancelled);
  });

  test('describes a multipart body by its fields and files', () async {
    await start();
    final dio = dioWith((o) async => json({'ok': true}));
    await dio.post<Object?>(
      'https://api.test/upload',
      data: FormData.fromMap({
        'caption': 'hello',
        'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.bin'),
      }),
    );
    final call = recorded().single;
    expect(call.request.headers.contentType, startsWith('multipart/form-data'));
    final text = utf8.decode(call.request.body.bytes);
    expect(text, contains('caption = hello'));
    expect(text, contains('file = a.bin (3 bytes'));
  });

  test('records a plain string response', () async {
    await start();
    final dio = dioWith(
      (o) async => ResponseBody.fromString(
        'hello',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      ),
    );
    await dio.get<Object?>('https://api.test/hi');
    expect(recorded().single.response!.body.text, 'hello');
  });

  test('a streamed response does not break the call', () async {
    await start();
    final dio = dioWith((o) async => json({'a': 1}));
    final reply = await dio.get<ResponseBody>(
      'https://api.test/s',
      options: Options(responseType: ResponseType.stream),
    );
    expect(reply.statusCode, 200);
    expect(recorded().single.state, FlutwireCallState.completed);
  });

  group('next to the dart:io capture', () {
    test('stands down, because that capture sees the call itself', () async {
      await start(captureDartIo: true);
      expect(Flutwire.wireCaptureActive, isTrue);
      final dio = dioWith((o) async => json({'id': 1}));
      await dio.get<Object?>('https://api.test/a');
      expect(recorded(), isEmpty);
    });

    test('records anyway when forced', () async {
      await start(captureDartIo: true);
      final dio = dioWith((o) async => json({'id': 1}), force: true);
      await dio.get<Object?>('https://api.test/a');
      expect(recorded(), hasLength(1));
    });
  });

  test('does nothing when Flutwire is not running', () async {
    final dio = dioWith((o) async => json({'ok': true}));
    final reply = await dio.get<Object?>('https://api.test/a');
    expect(reply.statusCode, 200);
    expect(Flutwire.calls.value, isEmpty);
  });
}
