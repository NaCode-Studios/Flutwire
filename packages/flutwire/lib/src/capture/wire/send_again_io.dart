import 'dart:async';
import 'dart:io';

import '../../engine.dart';
import '../../resend.dart';
import '../recorder.dart';
import 'wire_io.dart';

/// How long a request may wait for the connection, unless the app's own
/// client already says.
const Duration _connectTimeout = Duration(seconds: 30);

/// How long a request may run, from the moment its connection is open.
const Duration _defaultDeadline = Duration(minutes: 2);

/// Whether this platform can send a request again.
const bool canSendAgain = true;

/// Sends [request] through `dart:io` and records it as a call that repeats the
/// one it names. Returns the id of the recorded call as soon as the request is
/// on its way, or null when nothing was recorded. It does not wait for the
/// answer: the call fills in as the answer arrives, like any other.
///
/// The request goes out the way the app's own would, through the overrides the
/// app installed, so a proxy or a certificate rule it set applies here too. The
/// capture is taken out of the way, because this call is recorded once, by
/// itself, with the link to the call it repeats.
///
/// A request that has not been answered after [deadline] is aborted and
/// recorded as failed.
Future<int?> sendAgain(
  FlutwireEngine engine,
  FlutwireResend request, {
  Duration deadline = _defaultDeadline,
}) async {
  var inner = HttpClient();
  if (inner is FlutwireHttpClient) inner = inner.unwrapped;
  inner.connectionTimeout ??= _connectTimeout;
  final client = FlutwireHttpClient(inner, engine, resentFrom: request.from);
  final HttpClientRequest open;
  try {
    open = await client.openUrl(request.method, request.uri);
  } on Object {
    // The wrapper has already recorded the call as failed, with the reason.
    client.close();
    return client.lastRecorder?.id;
  }
  final recorder = client.lastRecorder;
  unawaited(_send(client, open, request, recorder, deadline));
  return recorder?.id;
}

Future<void> _send(
  FlutwireHttpClient client,
  HttpClientRequest open,
  FlutwireResend request,
  FlutwireCallRecorder? recorder,
  Duration deadline,
) async {
  final timer = Timer(deadline, () {
    recorder?.fail(
      TimeoutException('No answer within ${deadline.inSeconds} s', deadline),
    );
    open.abort();
  });
  try {
    // The first value of a field replaces what the client set by default, such
    // as the user agent. Any further value is added next to it.
    final seen = <String>{};
    for (final field in request.headers.entries) {
      if (seen.add(field.key.toLowerCase())) {
        open.headers.set(field.key, field.value, preserveHeaderCase: true);
      } else {
        open.headers.add(field.key, field.value, preserveHeaderCase: true);
      }
    }
    final body = request.body;
    if (body != null) {
      open.contentLength = body.length;
      open.add(body);
    }
    final response = await open.close();
    await response.drain<void>();
  } on Object catch (error, stack) {
    // A failure on the wire is already on record. What is left is a field the
    // client refuses and the abort above, and `fail` ignores a call that has
    // already ended.
    recorder?.fail(error, stack);
  } finally {
    timer.cancel();
    client.close();
  }
}
