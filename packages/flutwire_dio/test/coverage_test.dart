import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_dio/flutwire_dio.dart';

const _uri = 'https://api.test/a';

Future<void> start({bool captureDartIo = true}) => Flutwire.init(
  config: FlutwireConfig(
    enabled: true,
    persist: false,
    captureDartIo: captureDartIo,
    notification: const FlutwireNotificationConfig(enabled: false),
  ),
);

/// An adapter with a transport of its own, as `native_dio_adapter` has.
class _Native implements HttpClientAdapter {
  _Native({this.fails = false});

  final bool fails;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fails) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio dioWith(HttpClientAdapter? adapter, {bool force = false}) {
  final dio = Dio();
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.add(FlutwireDioInterceptor(force: force));
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Flutwire.reset();
    HttpOverrides.global = null;
  });

  group('an adapter that does not go through dart:io', () {
    test('is named in a note, because nothing records its calls', () async {
      await start();
      final dio = dioWith(_Native());

      await dio.get<Object?>(_uri);

      final note = Flutwire.coverage.value.single;
      expect(note.gap, FlutwireGap.clientBypassesDartIo);
      expect(note.subject, 'Dio · api.test');
      expect(Flutwire.calls.value, isEmpty);
    });

    test('is named in the note when the call fails too', () async {
      await start();
      final dio = dioWith(_Native(fails: true));

      await expectLater(dio.get<Object?>(_uri), throwsA(isA<DioException>()));

      expect(
        Flutwire.coverage.value.single.gap,
        FlutwireGap.clientBypassesDartIo,
      );
    });

    test('is no problem when the interceptor is told to record', () async {
      await start();
      final dio = dioWith(_Native(), force: true);

      await dio.get<Object?>(_uri);

      expect(Flutwire.coverage.value, isEmpty);
      expect(Flutwire.calls.value, hasLength(1));
    });
  });

  test('the default adapter goes through dart:io and leaves no note', () async {
    await start();
    final dio = dioWith(null);

    try {
      await dio.get<Object?>(_uri);
    } on Object {
      // The test binding refuses to connect, which does not matter here: the
      // capture saw the call before the refusal.
    }

    expect(Flutwire.coverage.value, isEmpty);
  });

  test(
    'without the capture the interceptor records and says nothing',
    () async {
      await start(captureDartIo: false);
      final dio = dioWith(_Native());

      await dio.get<Object?>(_uri);

      expect(Flutwire.coverage.value, isEmpty);
      expect(Flutwire.calls.value, hasLength(1));
    },
  );
}
