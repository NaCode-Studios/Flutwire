import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutwire/flutwire.dart';

/// Records the calls of a Dio instance in Flutwire.
///
/// ```dart
/// final dio = Dio()..interceptors.add(FlutwireDioInterceptor());
/// ```
///
/// Add it last, so that it sees the headers the other interceptors added. With
/// the `dart:io` capture installed, which is the default outside the web, it
/// stands down: that capture already sees the call, with the bytes that really
/// went over the wire, and recording it twice would only fill the list. Pass
/// [force] to record anyway, for an adapter that does not use `dart:io`.
///
/// What this interceptor records is the call as Dio sees it: the request data
/// before the transformer encodes it and the response data after the
/// transformer decoded it. A [FormData] body is described by its fields and
/// files rather than reproduced byte for byte.
final class FlutwireDioInterceptor extends Interceptor {
  /// Creates the interceptor.
  FlutwireDioInterceptor({this.force = false});

  /// Whether to record even when the `dart:io` capture is installed.
  final bool force;

  static const String _key = 'flutwire.recorder';
  static const String _watchKey = 'flutwire.standDown';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (force || !Flutwire.wireCaptureActive) {
      final recorder = Flutwire.begin(
        method: options.method,
        uri: options.uri,
        source: FlutwireSource.dio,
        requestHeaders: _requestHeaders(options),
      );
      if (recorder != null) {
        options.extra[_key] = recorder;
        final body = _encode(options.data);
        if (body != null) recorder.requestBody(body);
        recorder.requestSent();
      }
    } else {
      // The capture is meant to record this call. If the adapter does not go
      // through dart:io it never will, and Flutwire says so at the end.
      final watch = Flutwire.watchStandDown(
        method: options.method,
        uri: options.uri,
        client: 'Dio',
      );
      if (watch != null) options.extra[_watchKey] = watch;
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _finishWatch(response.requestOptions);
    final recorder = _take(response.requestOptions);
    if (recorder != null) {
      _recordResponse(recorder, response);
      recorder.complete();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _finishWatch(err.requestOptions);
    final recorder = _take(err.requestOptions);
    if (recorder != null) {
      final response = err.response;
      if (response != null) {
        _recordResponse(recorder, response);
        recorder.complete();
      } else if (err.type == DioExceptionType.cancel) {
        recorder.cancel();
      } else {
        recorder.fail(err, err.stackTrace);
      }
    }
    handler.next(err);
  }

  FlutwireCallRecorder? _take(RequestOptions options) {
    final value = options.extra[_key];
    return value is FlutwireCallRecorder ? value : null;
  }

  void _finishWatch(RequestOptions options) {
    final watch = options.extra.remove(_watchKey);
    if (watch is FlutwireStandDown) watch.finish();
  }

  void _recordResponse(FlutwireCallRecorder recorder, Response<dynamic> r) {
    recorder.responseHead(
      statusCode: r.statusCode ?? 0,
      reasonPhrase: r.statusMessage ?? '',
      headers: FlutwireHeaders([
        for (final entry in r.headers.map.entries)
          for (final value in entry.value) MapEntry(entry.key, value),
      ]),
      redirects: [
        for (final hop in r.redirects)
          FlutwireRedirect(
            statusCode: hop.statusCode,
            method: hop.method,
            location: hop.location,
          ),
      ],
    );
    final body = _encode(r.data);
    if (body != null) recorder.responseBody(body);
  }

  static FlutwireHeaders _requestHeaders(RequestOptions options) {
    final fields = <MapEntry<String, String>>[];
    var hasType = false;
    options.headers.forEach((name, value) {
      if (value == null) return;
      if (name.toLowerCase() == 'content-type') hasType = true;
      if (value is Iterable<Object?>) {
        for (final v in value) {
          fields.add(MapEntry(name, '$v'));
        }
      } else {
        fields.add(MapEntry(name, '$value'));
      }
    });
    if (!hasType) {
      final type = options.contentType ?? _guessType(options.data);
      if (type != null) fields.add(MapEntry('content-type', type));
    }
    return FlutwireHeaders(fields);
  }

  static String? _guessType(Object? data) {
    if (data is Map<Object?, Object?> || data is List<Object?>) {
      return Headers.jsonContentType;
    }
    if (data is FormData) {
      return 'multipart/form-data; boundary=${data.boundary}';
    }
    return null;
  }

  /// The bytes of [data] as Dio would send or has received them, or null when
  /// there is no way to read them without consuming a stream.
  static List<int>? _encode(Object? data) {
    if (data == null) return null;
    if (data is String) return utf8.encode(data);
    if (data is List<int>) return data;
    if (data is FormData) return utf8.encode(_describe(data));
    if (data is Map<Object?, Object?> || data is List<Object?>) {
      try {
        return utf8.encode(jsonEncode(data));
      } on Object {
        return utf8.encode('$data');
      }
    }
    if (data is Stream<Object?> || data is ResponseBody) return null;
    return utf8.encode('$data');
  }

  static String _describe(FormData form) {
    final out = StringBuffer('multipart/form-data\n');
    for (final field in form.fields) {
      out.writeln('${field.key} = ${field.value}');
    }
    for (final file in form.files) {
      final f = file.value;
      out.writeln(
        '${file.key} = ${f.filename ?? 'file'} (${f.length} bytes'
        '${f.contentType == null ? '' : ', ${f.contentType}'})',
      );
    }
    return out.toString().trimRight();
  }
}
