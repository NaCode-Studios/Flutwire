import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;

import '../config.dart';
import '../model/body.dart';
import '../model/call.dart';
import '../model/headers.dart';
import 'graphql.dart';

/// What a recorder needs from the engine that created it.
abstract interface class FlutwireRecorderHost {
  /// The configuration in force.
  FlutwireConfig get config;

  /// The current time. Tests replace it.
  DateTime now();

  /// Publishes a snapshot of a call. [finished] is true for the last one.
  void publish(FlutwireCall call, {required bool finished});

  /// Reports a failure inside Flutwire itself, which must never reach the app.
  void internalError(Object error, StackTrace stack);
}

/// Describes one call to Flutwire as it unfolds.
///
/// A capture adapter gets a recorder from `Flutwire.begin`, then reports what it
/// sees: request body chunks, the response head, response body chunks, and how
/// the call ended. The recorder keeps the first `maxBodyBytes` of each body,
/// counts the rest, hides what the redaction policy names, and publishes
/// snapshots for the inspector and the notification.
///
/// Nothing a recorder does can throw into the caller: a failure is reported to
/// the engine and the call is dropped from the history.
final class FlutwireCallRecorder {
  /// Creates a recorder for [call], which is published right away.
  ///
  /// Adapters get theirs from `Flutwire.begin`; this constructor is for the
  /// engine and for tests.
  @internal
  FlutwireCallRecorder(this._host, FlutwireCall call)
    : _call = call,
      _req = _BodyBuffer(_host.config.maxBodyBytes),
      _res = _BodyBuffer(_host.config.maxBodyBytes) {
    _publish(finished: false);
  }

  final FlutwireRecorderHost _host;
  final _BodyBuffer _req;
  final _BodyBuffer _res;
  FlutwireCall _call;
  bool _requestFinal = false;
  bool _finished = false;
  String? _contentType;
  DateTime? _lastProgress;
  int _publishedResponseBytes = -1;

  /// The latest published snapshot.
  FlutwireCall get snapshot => _call;

  /// The id of the call.
  int get id => _call.id;

  /// Whether the call has ended. Later reports are ignored.
  bool get isFinished => _finished;

  /// Adds a chunk of the request body.
  void requestBody(List<int> chunk) => _guard(() {
    if (_requestFinal || _finished) return;
    _req.add(chunk);
  });

  /// Replaces the request headers, for a client that learns them after the
  /// call began. The redaction policy is applied.
  void requestHeaders(FlutwireHeaders headers) => _guard(() {
    if (_requestFinal || _finished) return;
    _call = _call.copyWith(
      request: _call.request.copyWith(
        headers: _host.config.redaction.applyToHeaders(headers),
      ),
    );
    _contentType = headers.contentType;
  });

  /// Says the request has been sent in full, fixing the request body.
  void requestSent() => _guard(_finishRequest);

  /// Reports the response head. Calling it a second time, as a client does
  /// after following a redirect, replaces the first.
  void responseHead({
    required int statusCode,
    required FlutwireHeaders headers,
    String reasonPhrase = '',
    String? remoteAddress,
    int? remotePort,
    FlutwireCertificate? certificate,
    List<FlutwireRedirect> redirects = const [],
    String? compression,
  }) => _guard(() {
    if (_finished) return;
    _finishRequest();
    final redacted = _host.config.redaction.applyToHeaders(headers);
    _call = _call.copyWith(
      firstByteAt: _host.now(),
      response: FlutwireResponse(
        statusCode: statusCode,
        reasonPhrase: reasonPhrase,
        headers: redacted,
        body: FlutwireBody(
          bytes: Uint8List(0),
          totalBytes: 0,
          contentType: headers.contentType,
        ),
        remoteAddress: remoteAddress,
        remotePort: remotePort,
        certificate: certificate,
        redirects: redirects,
        compression: compression,
      ),
    );
    _publish(finished: false);
  });

  /// Adds a chunk of the response body.
  void responseBody(List<int> chunk) => _guard(() {
    if (_finished) return;
    _res.add(chunk);
    final now = _host.now();
    final last = _lastProgress;
    if (last != null && now.difference(last) < _progressInterval) return;
    _lastProgress = now;
    _publishProgress();
  });

  /// Passes [source], the bytes of the request body, through unchanged while
  /// recording them. Use it for a body that is only available as a stream.
  Stream<List<int>> observeRequest(Stream<List<int>> source) =>
      source.map((chunk) {
        requestBody(chunk);
        return chunk;
      });

  /// Passes [source], the bytes of the response body, through unchanged while
  /// recording them, and ends the call when the stream ends, fails, or is
  /// cancelled by the app.
  ///
  /// The returned stream has the semantics of [source]: it is paused, resumed
  /// and cancelled with it, so reading through it cannot change how fast, or
  /// whether, the app gets its bytes.
  Stream<List<int>> observeResponse(Stream<List<int>> source) {
    late final StreamController<List<int>> out;
    StreamSubscription<List<int>>? subscription;
    out = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(
          (chunk) {
            responseBody(chunk);
            out.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            fail(error, stack);
            out.addError(error, stack);
          },
          onDone: () {
            complete();
            out.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        cancel();
        return subscription?.cancel();
      },
    );
    return out.stream;
  }

  /// Ends the call: the response, if any, was read to its end.
  void complete() => _end(FlutwireCallState.completed);

  /// Ends the call because it failed with [error].
  void fail(Object error, [StackTrace? stack]) => _end(
    FlutwireCallState.failed,
    error: FlutwireError(
      type: error.runtimeType.toString(),
      message: error.toString(),
      stack: stack?.toString(),
    ),
  );

  /// Ends the call because the app stopped reading it or aborted it.
  void cancel() => _end(FlutwireCallState.cancelled);

  static const Duration _progressInterval = Duration(milliseconds: 200);

  void _end(FlutwireCallState state, {FlutwireError? error}) => _guard(() {
    if (_finished) return;
    _finishRequest();
    _finished = true;
    final res = _call.response;
    _call = _call.copyWith(
      state: state,
      endedAt: _host.now(),
      error: error,
      response: res?.copyWith(body: _responseBody(res.headers.contentType)),
    );
    _publish(finished: true);
  });

  void _finishRequest() {
    if (_requestFinal) return;
    _requestFinal = true;
    final headers = _call.request.headers;
    final contentType = _contentType ?? headers.contentType;
    final redaction = _host.config.redaction;
    final raw = _req.bytes();
    final body = FlutwireBody(
      bytes: redaction.applyToBody(raw, contentType: contentType),
      totalBytes: _req.total,
      contentType: contentType,
    );
    _call = _call.copyWith(
      request: _call.request.copyWith(body: body),
      graphql: detectGraphql(
        method: _call.method,
        uri: _call.uri,
        headers: headers,
        body: body,
      ),
    );
    _publish(finished: false);
  }

  void _publishProgress() {
    final res = _call.response;
    if (res == null || _res.total == _publishedResponseBytes) return;
    _publishedResponseBytes = _res.total;
    _call = _call.copyWith(
      response: res.copyWith(body: _responseBody(res.headers.contentType)),
    );
    _publish(finished: false);
  }

  FlutwireBody _responseBody(String? contentType) => FlutwireBody(
    bytes: _host.config.redaction.applyToBody(
      _res.bytes(),
      contentType: contentType,
    ),
    totalBytes: _res.total,
    contentType: contentType,
  );

  void _publish({required bool finished}) =>
      _guard(() => _host.publish(_call, finished: finished));

  void _guard(void Function() body) {
    try {
      body();
    } catch (error, stack) {
      try {
        _host.internalError(error, stack);
      } catch (_) {
        // Reporting is best effort too: the app's request comes first.
      }
    }
  }
}

/// Keeps the first bytes of a body and counts all of them.
class _BodyBuffer {
  _BodyBuffer(this.cap);

  final int cap;
  final BytesBuilder _builder = BytesBuilder();
  Uint8List? _cached;

  /// Every byte seen, kept or not.
  int total = 0;

  void add(List<int> chunk) {
    total += chunk.length;
    final room = cap - _builder.length;
    if (room <= 0 || chunk.isEmpty) return;
    _cached = null;
    _builder.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
  }

  /// The bytes kept so far. The same instance is returned until more arrive.
  Uint8List bytes() => _cached ??= _builder.toBytes();
}
