import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import '../../engine.dart';
import '../../intercept/breakpoints.dart';
import '../../intercept/rule.dart';
import '../../model/call.dart';
import '../../model/headers.dart';
import '../../resend.dart';
import '../recorder.dart';
import 'wire_forward_io.dart';

/// A request that a breakpoint holds before it leaves.
///
/// The app uses it as any other request: it sets header fields on it and writes
/// to it. What it writes is kept here and sent nowhere. When the app closes the
/// request it is put on hold, and it stays there, with the app waiting, until
/// somebody lets it go. It then goes out on a connection of its own, as it was
/// or as it was changed, and the app gets the answer as if nothing had been in
/// the way. The connection the app opened is not used, because by then it may
/// have been closed by a server that got tired of waiting.
///
/// A request that went out as it was is one call. One that was changed ends the
/// call the app made, which never left, and is recorded as another call that
/// repeats it.
final class HeldHttpClientRequest extends ForwardingHttpClientRequest {
  /// Holds [inner] when the app closes it.
  ///
  /// [client] is the one that opened [inner], without the recording, and it
  /// sends the request that is let go. [wrapResponse] puts the recording around
  /// a response. [track] says that a recorder has a call that is not over, and
  /// [onFinished] that this request is no longer held.
  HeldHttpClientRequest(
    super.inner, {
    required this.client,
    required this.engine,
    required this.breakpoints,
    required this.rule,
    required this.recorder,
    required this.wrapResponse,
    required this.track,
    required this.onFinished,
  }) {
    // The app may never ask for the answer.
    _done.future.ignore();
  }

  /// The client that sends the request when it is let go.
  final HttpClient client;

  /// The engine, which records the call that a changed request becomes.
  final FlutwireEngine engine;

  /// Where the request is held.
  final FlutwireBreakpoints breakpoints;

  /// The breakpoint that holds it.
  final FlutwireRule rule;

  /// The recorder of the call the app made, or null when it is not recorded.
  final FlutwireCallRecorder? recorder;

  /// Puts the recording of a call around a response.
  final HttpClientResponse Function(
    HttpClientResponse response,
    FlutwireCallRecorder recorder,
  )
  wrapResponse;

  /// Says that a call has begun and has not ended.
  final void Function(FlutwireCallRecorder? recorder) track;

  /// Says that this request is no longer held.
  final void Function(HeldHttpClientRequest request) onFinished;

  final BytesBuilder _body = BytesBuilder();
  final Completer<HttpClientResponse> _done = Completer();
  Future<HttpClientResponse>? _closing;
  Object? _failure;
  StackTrace? _failureStack;
  int? _heldId;
  bool _aborted = false;

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  void add(List<int> data) {
    if (_closing != null) return;
    _body.add(data);
    recorder?.requestBody(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _failure ??= error;
    _failureStack ??= stackTrace;
  }

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => stream.forEach(add);

  /// Nothing has been sent, and flushing is not going to change that.
  @override
  Future<dynamic> flush() => Future.value();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    if (_aborted) return;
    _aborted = true;
    final id = _heldId;
    if (id != null) breakpoints.stop(id);
    recorder?.cancel();
    _abortInner();
    if (!_done.isCompleted) {
      _done.completeError(
        exception ?? const HttpException('The request was aborted'),
        stackTrace,
      );
    }
    onFinished(this);
  }

  /// Stops the request if it is being held, for a client that is closed while
  /// it waits.
  void stopWhileHeld() {
    final id = _heldId;
    if (id != null) breakpoints.stop(id);
  }

  @override
  Future<HttpClientResponse> close() => _closing ??= _hold();

  Future<HttpClientResponse> _hold() async {
    final failure = _failure;
    if (failure != null) return _fail(failure, _failureStack);
    final sent = _headersAsSent();
    final body = _body.takeBytes();
    recorder?.requestHeaders(sent);
    recorder?.requestSent();
    final ticket = breakpoints.hold(
      method: inner.method,
      uri: inner.uri,
      headers: sent,
      body: body,
      ruleId: rule.id,
    );
    _heldId = ticket.id;
    final answer = await ticket.answer;
    _heldId = null;
    if (_aborted) {
      throw const HttpException('The request was aborted while it was held');
    }
    if (answer == null) {
      recorder?.endHeld(
        'Stopped at a breakpoint.',
        state: FlutwireCallState.failed,
      );
      return _fail(
        HttpException(
          'The request was stopped at a Flutwire breakpoint',
          uri: inner.uri,
        ),
        null,
      );
    }
    final unchanged = _sameToSend(answer, sent, body);
    final target = unchanged ? recorder : _recordChanged(answer);
    if (unchanged) {
      // It is the same call, and how long it took includes the time it was held.
      recorder?.intercepted(FlutwireIntercept.held);
    } else {
      recorder?.endHeld(
        target == null
            ? 'Held at a breakpoint and sent with changes.'
            : 'Held at a breakpoint and sent with changes, as another call.',
        state: FlutwireCallState.cancelled,
      );
    }
    final HttpClientResponse response;
    try {
      response = await _send(answer);
    } on Object catch (error, stack) {
      target?.fail(error, stack);
      return _fail(error, stack);
    } finally {
      _abortInner();
    }
    final wrapped = target == null ? response : wrapResponse(response, target);
    _done.complete(wrapped);
    onFinished(this);
    return wrapped;
  }

  Future<HttpClientResponse> _fail(Object error, StackTrace? stack) {
    recorder?.fail(error, stack);
    _abortInner();
    if (!_done.isCompleted) _done.completeError(error, stack);
    onFinished(this);
    return Future.error(error, stack);
  }

  /// The fields of the request as they would have gone out, the cookies the
  /// app added included, as the real values: this is the request itself, not
  /// its record.
  FlutwireHeaders _headersAsSent() {
    final fields = <MapEntry<String, String>>[];
    inner.headers.forEach((name, values) {
      for (final value in values) {
        fields.add(MapEntry(name, value));
      }
    });
    if (inner.cookies.isNotEmpty) {
      fields.add(
        MapEntry(
          HttpHeaders.cookieHeader,
          inner.cookies.map((c) => '${c.name}=${c.value}').join('; '),
        ),
      );
    }
    return FlutwireHeaders(fields);
  }

  /// Whether [answer] asks for what the app asked for. The fields the client
  /// writes itself are left out of the comparison, because the editor does not
  /// show them and the client writes them again.
  bool _sameToSend(
    FlutwireHeldRequest answer,
    FlutwireHeaders sent,
    Uint8List body,
  ) =>
      answer.method == inner.method &&
      answer.uri == inner.uri &&
      listEquals(answer.body, body) &&
      _editable(answer.headers) == _editable(sent);

  static FlutwireHeaders _editable(FlutwireHeaders headers) => FlutwireHeaders([
    for (final field in headers.entries)
      if (!clientManagedHeaders.contains(field.key.toLowerCase())) field,
  ]);

  /// Starts the call that [answer] becomes, which repeats the one the app made.
  FlutwireCallRecorder? _recordChanged(FlutwireHeldRequest answer) {
    final original = recorder;
    if (original == null) return null;
    final next = engine.begin(
      method: answer.method,
      uri: answer.uri,
      source: FlutwireSource.io,
      requestHeaders: answer.headers,
      resentFrom: original.id,
    );
    if (next == null) return null;
    next.intercepted(FlutwireIntercept.edited);
    if (answer.body.isNotEmpty) next.requestBody(answer.body);
    next.requestSent();
    track(next);
    return next;
  }

  /// Sends [answer] on a connection of its own.
  Future<HttpClientResponse> _send(FlutwireHeldRequest answer) async {
    final fresh = await client.openUrl(answer.method, answer.uri);
    fresh
      ..followRedirects = inner.followRedirects
      ..maxRedirects = inner.maxRedirects
      ..persistentConnection = inner.persistentConnection
      // The whole body is here, so the client can say how long it is.
      ..bufferOutput = true;
    _writeFields(fresh.headers, answer.headers);
    if (answer.body.isNotEmpty) fresh.add(answer.body);
    return fresh.close();
  }

  /// Makes [target] hold the fields in [wanted] and no others, apart from the
  /// ones the client writes by itself.
  static void _writeFields(HttpHeaders target, FlutwireHeaders wanted) {
    final names = {for (final name in wanted.names) name.toLowerCase()};
    final stale = <String>[];
    target.forEach((name, _) {
      final lower = name.toLowerCase();
      if (!names.contains(lower) && !clientManagedHeaders.contains(lower)) {
        stale.add(name);
      }
    });
    stale.forEach(target.removeAll);
    for (final name in wanted.names) {
      if (clientManagedHeaders.contains(name.toLowerCase())) continue;
      target.removeAll(name);
      for (final value in wanted[name]) {
        target.add(name, value, preserveHeaderCase: true);
      }
    }
  }

  void _abortInner() {
    try {
      inner.abort();
    } on Object {
      // The request is over either way.
    }
  }
}
