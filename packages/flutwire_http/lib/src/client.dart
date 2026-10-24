import 'dart:convert';

import 'package:flutwire/flutwire.dart';
import 'package:http/http.dart';

/// A `package:http` client that records its calls in Flutwire, then lets
/// [_inner] do the work.
///
/// ```dart
/// final client = FlutwireClient(Client());
/// ```
///
/// With the `dart:io` capture installed, which is the default outside the web,
/// it stands down: that capture already sees the call with the bytes that
/// really went over the wire, and recording it twice would only fill the list.
/// Pass [force] to record anyway.
///
/// A [MultipartRequest] is described by its fields and files rather than
/// reproduced byte for byte, because its body can only be read once, by the
/// client that sends it.
class FlutwireClient extends BaseClient {
  /// Wraps [_inner]. Pass [force] to record even when the `dart:io` capture
  /// is installed, for a client that does not go through `dart:io`.
  FlutwireClient(this._inner, {this.force = false});

  final Client _inner;

  /// Whether to record even when the `dart:io` capture is installed.
  final bool force;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    if (!force && Flutwire.wireCaptureActive) {
      // The capture is meant to record this call. If the inner client does not
      // go through dart:io it never will, and Flutwire says so at the end.
      final watch = Flutwire.watchStandDown(
        method: request.method,
        uri: request.url,
        client: 'FlutwireClient over ${_inner.runtimeType}',
      );
      try {
        return await _inner.send(request);
      } finally {
        watch?.finish();
      }
    }
    final recorder = Flutwire.begin(
      method: request.method,
      uri: request.url,
      source: FlutwireSource.http,
      requestHeaders: FlutwireHeaders.fromMap(request.headers),
    );
    if (recorder == null) return _inner.send(request);

    if (request is Request) {
      recorder.requestBody(request.bodyBytes);
    } else if (request is MultipartRequest) {
      recorder.requestBody(utf8.encode(_describe(request)));
    }
    recorder.requestSent();

    final StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error, stack) {
      recorder.fail(error, stack);
      rethrow;
    }
    recorder.responseHead(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase ?? '',
      headers: FlutwireHeaders.fromMap(response.headers),
    );
    return StreamedResponse(
      recorder.observeResponse(response.stream),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

  static String _describe(MultipartRequest request) {
    final out = StringBuffer('multipart/form-data\n');
    request.fields.forEach((name, value) => out.writeln('$name = $value'));
    for (final file in request.files) {
      out.writeln(
        '${file.field} = ${file.filename ?? 'file'} (${file.length} bytes, '
        '${file.contentType})',
      );
    }
    return out.toString().trimRight();
  }
}
