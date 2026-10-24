import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show internal;

import '../config.dart';
import '../model/body.dart';
import '../model/call.dart';
import '../model/headers.dart';
import '../model/message.dart';
import 'graphql.dart';
import 'messages/message_log.dart';
import 'messages/sse_parser.dart';

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
  final Completer<void> _done = Completer<void>();
  bool _requestFinal = false;
  bool _finished = false;
  String? _contentType;
  DateTime? _lastProgress;
  int _publishedResponseBytes = -1;
  final MessageLog _messages = MessageLog();
  FlutwireConversationKind? _conversation;
  DateTime? _lastMessagePublish;
  Timer? _messageTimer;
  SseParser? _sse;

  /// The latest published snapshot.
  FlutwireCall get snapshot => _call;

  /// The id of the call.
  int get id => _call.id;

  /// Whether the call has ended. Later reports are ignored.
  bool get isFinished => _finished;

  /// Completes when the call has ended, however it ended.
  Future<void> get done => _done.future;

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
  ///
  /// A response that has no body ends the call here: the answer to a HEAD
  /// request, a 204, a 304 and one that says it is empty. A client reads such a
  /// body only when it wants to, and most never do, so waiting for the stream
  /// to end would leave the call running for as long as the app does. A
  /// redirect is left open, because the client may follow it and report the
  /// head of what it finds.
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
    _sse =
        (headers.contentType ?? '').toLowerCase().contains('text/event-stream')
        ? SseParser(_onEvent, maxChars: _host.config.maxBodyBytes)
        : null;
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
    if (_endsAtHead(statusCode, headers)) {
      _end(FlutwireCallState.completed);
    } else {
      _publish(finished: false);
    }
  });

  /// Adds a chunk of the response body.
  void responseBody(List<int> chunk) => _guard(() {
    if (_finished) return;
    _res.add(chunk);
    _sse?.add(chunk);
    final now = _host.now();
    final last = _lastProgress;
    if (last != null && now.difference(last) < _progressInterval) return;
    _lastProgress = now;
    _publishProgress();
  });

  /// Says that the call carries a conversation from now on, which a WebSocket
  /// does after its handshake. The call then has a list of messages, empty
  /// until the first one arrives. Reporting a message does the same.
  void startConversation(FlutwireConversationKind kind) => _guard(() {
    if (_finished || _conversation != null) return;
    _conversation = kind;
    if (kind == FlutwireConversationKind.webSocket) {
      _call = _call.copyWith(uri: _webSocketAddress(_call.uri));
    }
    _publishMessages(force: true);
  });

  /// Adds a message to the conversation: a WebSocket message or frame, or a
  /// server-sent event. [sent] is true for what the app sent.
  ///
  /// Only the first `maxBodyBytes` of [payload] are kept, and [totalBytes] is
  /// the size of the whole, which defaults to the length of [payload]. Only the
  /// latest messages are kept, to bound what a conversation that runs for hours
  /// can hold; the count of all of them is kept.
  void message({
    required bool sent,
    required FlutwireMessageKind kind,
    required List<int> payload,
    int? totalBytes,
    String? event,
    String? eventId,
    bool undecoded = false,
  }) => _guard(() {
    if (_finished) return;
    _conversation ??= kind == FlutwireMessageKind.event
        ? FlutwireConversationKind.eventStream
        : FlutwireConversationKind.webSocket;
    final cap = _host.config.maxBodyBytes;
    var bytes = payload is Uint8List ? payload : Uint8List.fromList(payload);
    if (bytes.length > cap) bytes = bytes.sublist(0, cap);
    if (kind == FlutwireMessageKind.text || kind == FlutwireMessageKind.event) {
      bytes = _host.config.redaction.applyToBody(bytes, contentType: null);
    }
    _messages.add(
      FlutwireMessage(
        index: _messages.total,
        sent: sent,
        at: _host.now(),
        kind: kind,
        bytes: bytes,
        totalBytes: totalBytes ?? payload.length,
        event: event,
        eventId: eventId,
        undecoded: undecoded,
      ),
    );
    _publishMessages(force: false);
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
            unawaited(out.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        cancel();
        await subscription?.cancel();
      },
    );
    return out.stream;
  }

  /// Says how a rule of the user's touched the call, which the list marks.
  @internal
  void intercepted(FlutwireIntercept how) => _guard(() {
    if (_finished) return;
    _call = _call.copyWith(intercept: how);
    _publish(finished: false);
  });

  /// Ends a call that was held at a breakpoint and did not go out as the app
  /// made it, for the reason in [message]. It ends in [state], which is
  /// `failed` when the app is told the request did not work and `cancelled`
  /// when a changed copy took its place.
  @internal
  void endHeld(String message, {required FlutwireCallState state}) =>
      _guard(() {
        if (_finished) return;
        _call = _call.copyWith(intercept: FlutwireIntercept.held);
        _end(
          state,
          error: FlutwireError(type: 'Breakpoint', message: message),
        );
      });

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

  static const Set<int> _redirectStatuses = {301, 302, 303, 307, 308};

  /// Whether nothing can follow the head of this response, so that the call is
  /// over with it. RFC 9110, section 6.4.1, says which responses have no body.
  bool _endsAtHead(int statusCode, FlutwireHeaders headers) {
    // After a protocol switch come the bytes of the new protocol, and a client
    // may follow a redirect and report the head of what it finds.
    if (statusCode < 200 || _redirectStatuses.contains(statusCode)) {
      return false;
    }
    return _call.method == 'HEAD' ||
        statusCode == 204 ||
        statusCode == 304 ||
        int.tryParse(headers.first('content-length')?.trim() ?? '') == 0;
  }

  /// The address of a WebSocket as the app wrote it. The handshake is an HTTP
  /// request, so the capture is handed an `http` or `https` address, with a
  /// port of 0 when the app gave none and an empty fragment.
  static Uri _webSocketAddress(Uri handshake) => Uri(
    scheme: switch (handshake.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      final other => other,
    },
    userInfo: handshake.userInfo.isEmpty ? null : handshake.userInfo,
    host: handshake.host,
    port: handshake.hasPort && handshake.port != 0 ? handshake.port : null,
    path: handshake.path.isEmpty ? '/' : handshake.path,
    query: handshake.query.isEmpty ? null : handshake.query,
    fragment: handshake.fragment.isEmpty ? null : handshake.fragment,
  );

  void _onEvent(SseEvent event) => message(
    sent: false,
    kind: FlutwireMessageKind.event,
    payload: Uint8List.fromList(utf8.encode(event.data)),
    totalBytes: event.totalBytes,
    event: event.event,
    eventId: event.id,
  );

  /// Puts the messages in a new snapshot. Messages come in bursts, so this
  /// publishes at most every [_progressInterval] and leaves the rest to a timer
  /// that fires once the burst is over.
  void _publishMessages({required bool force}) {
    final kind = _conversation;
    if (kind == null) return;
    final now = _host.now();
    final last = _lastMessagePublish;
    if (!force && last != null && now.difference(last) < _progressInterval) {
      _messageTimer ??= Timer(_progressInterval, () {
        _messageTimer = null;
        _guard(() => _publishMessages(force: true));
      });
      return;
    }
    _messageTimer?.cancel();
    _messageTimer = null;
    _lastMessagePublish = now;
    _call = _call.copyWith(messages: _messages.snapshot(kind));
    _publish(finished: false);
  }

  void _end(FlutwireCallState state, {FlutwireError? error}) => _guard(() {
    if (_finished) return;
    _finishRequest();
    _finished = true;
    _messageTimer?.cancel();
    _messageTimer = null;
    _sse?.close();
    final res = _call.response;
    final conversation = _conversation;
    _call = _call.copyWith(
      state: state,
      endedAt: _host.now(),
      error: error,
      response: res?.copyWith(body: _responseBody(res.headers.contentType)),
      messages: conversation == null ? null : _messages.snapshot(conversation),
    );
    _publish(finished: true);
    _done.complete();
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
    } on Object catch (error, stack) {
      try {
        _host.internalError(error, stack);
      } on Object {
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
