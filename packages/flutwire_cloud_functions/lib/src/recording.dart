import 'dart:convert';

import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:flutwire/flutwire.dart';

/// One callable call being written into the history.
///
/// It records what the Firebase SDK puts on the wire, so a callable looks like
/// the call it is: a POST whose body is `{"data": ...}` and whose reply is
/// `{"result": ...}`, or `{"error": ...}` with the status Firebase gives each
/// error code. Nothing here can throw into the call: a failure to record is a
/// call that is not recorded.
class Recording {
  Recording._(this._recorder);

  final FlutwireCallRecorder _recorder;
  bool _headSent = false;

  /// Starts recording a call to [endpoint] with [parameters], or returns null
  /// when this call is not to be recorded.
  static Recording? start(Uri endpoint, Object? parameters) {
    try {
      final recorder = Flutwire.begin(
        method: 'CALL',
        uri: endpoint,
        source: FlutwireSource.functions,
        requestHeaders: FlutwireHeaders.fromMap(const {
          'content-type': 'application/json; charset=utf-8',
        }),
      );
      if (recorder == null) return null;
      recorder
        ..requestBody(utf8.encode(_json({'data': parameters})))
        ..requestSent();
      return Recording._(recorder);
    } on Object {
      return null;
    }
  }

  /// The call returned [data].
  void succeeded(Object? data) => _guard(() {
    _head(200, 'OK');
    _recorder
      ..responseBody(utf8.encode(_json({'result': data})))
      ..complete();
  });

  /// One event of a stream arrived.
  void event(Object? event) => _guard(() {
    _head(200, 'OK');
    _recorder.responseBody(utf8.encode('${_json(event)}\n'));
  });

  /// The stream ended.
  void streamEnded() => _guard(() {
    _head(200, 'OK');
    _recorder.complete();
  });

  /// The listener of a stream went away.
  void cancelled() => _guard(_recorder.cancel);

  /// The call threw [error].
  void failed(Object error, StackTrace stack) => _guard(() {
    if (error is FirebaseFunctionsException) {
      final status = _statusOf(error.code);
      // These codes are as likely to come from the network as from the
      // function, and an exception cannot tell which, so they are shown as a
      // call that got no answer.
      if (status != null) {
        _head(status.http, error.code);
        _recorder
          ..responseBody(
            utf8.encode(
              _json({
                'error': {
                  'message': error.message,
                  'status': status.name,
                  if (error.details != null) 'details': error.details,
                },
              }),
            ),
          )
          ..complete();
        return;
      }
    }
    _recorder.fail(error, stack);
  });

  void _head(int statusCode, String reason) {
    if (_headSent) return;
    _headSent = true;
    _recorder.responseHead(
      statusCode: statusCode,
      reasonPhrase: reason,
      headers: FlutwireHeaders.fromMap(const {
        'content-type': 'application/json; charset=utf-8',
      }),
    );
  }

  void _guard(void Function() body) {
    try {
      body();
    } on Object {
      // Recording never changes what the app sees.
    }
  }

  static String _json(Object? value) {
    try {
      return jsonEncode(value, toEncodable: (object) => object.toString());
    } on Object {
      return '"(not JSON)"';
    }
  }

  /// The status Firebase answers with for an error [code], or null when the
  /// code says the call never completed.
  static ({int http, String name})? _statusOf(String code) => switch (code) {
    'invalid-argument' => (http: 400, name: 'INVALID_ARGUMENT'),
    'failed-precondition' => (http: 400, name: 'FAILED_PRECONDITION'),
    'out-of-range' => (http: 400, name: 'OUT_OF_RANGE'),
    'unauthenticated' => (http: 401, name: 'UNAUTHENTICATED'),
    'permission-denied' => (http: 403, name: 'PERMISSION_DENIED'),
    'not-found' => (http: 404, name: 'NOT_FOUND'),
    'already-exists' => (http: 409, name: 'ALREADY_EXISTS'),
    'aborted' => (http: 409, name: 'ABORTED'),
    'resource-exhausted' => (http: 429, name: 'RESOURCE_EXHAUSTED'),
    'internal' => (http: 500, name: 'INTERNAL'),
    'data-loss' => (http: 500, name: 'DATA_LOSS'),
    'unimplemented' => (http: 501, name: 'UNIMPLEMENTED'),
    _ => null,
  };
}
