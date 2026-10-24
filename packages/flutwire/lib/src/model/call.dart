import 'package:flutter/foundation.dart';

import 'body.dart';
import 'headers.dart';
import 'message.dart';

/// Where in the networking stack a call was recorded.
enum FlutwireSource {
  /// `dart:io`, which every `HttpClient`-based package ends up in.
  io('dart:io'),

  /// A Dio interceptor.
  dio('Dio'),

  /// A `package:http` client wrapper.
  http('http'),

  /// The Firebase Cloud Functions adapter, which records callable functions.
  /// They travel through the native SDK, so the `dart:io` capture never sees
  /// them.
  functions('Cloud Functions'),

  /// An adapter written by the app.
  custom('custom');

  const FlutwireSource(this.label);

  /// The name shown in the inspector.
  final String label;
}

/// How far a call got.
enum FlutwireCallState {
  /// The request was sent and the response is not finished.
  pending,

  /// A response arrived and its body ended. An HTTP error status is still a
  /// completed call: the server answered.
  completed,

  /// No usable response: the connection failed, timed out, or broke mid-body.
  failed,

  /// The app stopped reading, or aborted the request, before it finished.
  cancelled,
}

/// The family of an HTTP status code.
enum FlutwireStatusClass {
  /// No status yet, or none at all because the call failed.
  none,

  /// 1xx.
  informational,

  /// 2xx.
  success,

  /// 3xx.
  redirect,

  /// 4xx.
  clientError,

  /// 5xx.
  serverError;

  /// The class of [statusCode], or [none] for null.
  static FlutwireStatusClass of(int? statusCode) {
    if (statusCode == null) return none;
    return switch (statusCode ~/ 100) {
      1 => informational,
      2 => success,
      3 => redirect,
      4 => clientError,
      5 => serverError,
      _ => none,
    };
  }
}

/// How Flutwire took part in a call, for the calls it did.
///
/// Flutwire reads traffic and changes none, except what a rule the user made
/// asks for. These say which calls such a rule touched.
enum FlutwireIntercept {
  /// A mock rule answered the request, and nothing was sent.
  mocked,

  /// The request was held at a breakpoint and sent with changes. The call it
  /// replaced is the one it repeats.
  edited,

  /// The request was held at a breakpoint and did not go as it was: it was
  /// stopped there, or sent again with changes as another call.
  held,
}

/// A hop the client followed on the way to the final response.
@immutable
final class FlutwireRedirect {
  /// Creates a redirect record.
  const FlutwireRedirect({
    required this.statusCode,
    required this.method,
    required this.location,
  });

  /// Restores a redirect written by [toJson].
  factory FlutwireRedirect.fromJson(Map<String, Object?> json) =>
      FlutwireRedirect(
        statusCode: (json['status'] as num?)?.toInt() ?? 0,
        method: json['method'] as String? ?? 'GET',
        location: Uri.parse(json['location'] as String? ?? ''),
      );

  /// The status that asked for the hop, such as 302.
  final int statusCode;

  /// The method used for the next request.
  final String method;

  /// Where the next request went.
  final Uri location;

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'status': statusCode,
    'method': method,
    'location': location.toString(),
  };
}

/// The server certificate of a secure connection.
@immutable
final class FlutwireCertificate {
  /// Creates a certificate description.
  const FlutwireCertificate({
    required this.subject,
    required this.issuer,
    this.validFrom,
    this.validTo,
    this.sha1,
  });

  /// Restores a certificate written by [toJson].
  factory FlutwireCertificate.fromJson(Map<String, Object?> json) =>
      FlutwireCertificate(
        subject: json['subject'] as String? ?? '',
        issuer: json['issuer'] as String? ?? '',
        validFrom: DateTime.tryParse(json['from'] as String? ?? ''),
        validTo: DateTime.tryParse(json['to'] as String? ?? ''),
        sha1: json['sha1'] as String?,
      );

  /// Who the certificate was issued to.
  final String subject;

  /// Who issued it.
  final String issuer;

  /// The start of its validity.
  final DateTime? validFrom;

  /// The end of its validity.
  final DateTime? validTo;

  /// The SHA-1 fingerprint as hex.
  final String? sha1;

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'subject': subject,
    'issuer': issuer,
    'from': validFrom?.toIso8601String(),
    'to': validTo?.toIso8601String(),
    'sha1': sha1,
  };
}

/// What the app sent.
@immutable
final class FlutwireRequest {
  /// Creates a request record.
  const FlutwireRequest({required this.headers, required this.body});

  /// The header fields as they were sent.
  final FlutwireHeaders headers;

  /// The body, empty for a GET.
  final FlutwireBody body;

  /// A copy with the given parts replaced.
  FlutwireRequest copyWith({FlutwireHeaders? headers, FlutwireBody? body}) =>
      FlutwireRequest(
        headers: headers ?? this.headers,
        body: body ?? this.body,
      );
}

/// What the server answered.
@immutable
final class FlutwireResponse {
  /// Creates a response record.
  const FlutwireResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.reasonPhrase = '',
    this.remoteAddress,
    this.remotePort,
    this.certificate,
    this.redirects = const [],
    this.compression,
  });

  /// The status code, such as 200.
  final int statusCode;

  /// The reason phrase, such as `OK`; empty when the protocol has none.
  final String reasonPhrase;

  /// The header fields as they arrived.
  final FlutwireHeaders headers;

  /// The body, after the client decompressed it.
  final FlutwireBody body;

  /// The server's IP address, when the client reports it.
  final String? remoteAddress;

  /// The server's port, when the client reports it.
  final int? remotePort;

  /// The certificate of a secure connection.
  final FlutwireCertificate? certificate;

  /// The hops followed before this response, in order.
  final List<FlutwireRedirect> redirects;

  /// How the body was compressed on the wire, such as `gzip`, if it was.
  final String? compression;

  /// A copy with the given parts replaced.
  FlutwireResponse copyWith({FlutwireBody? body}) => FlutwireResponse(
    statusCode: statusCode,
    reasonPhrase: reasonPhrase,
    headers: headers,
    body: body ?? this.body,
    remoteAddress: remoteAddress,
    remotePort: remotePort,
    certificate: certificate,
    redirects: redirects,
    compression: compression,
  );
}

/// Why a call failed.
@immutable
final class FlutwireError {
  /// Creates an error record.
  const FlutwireError({required this.type, required this.message, this.stack});

  /// Restores an error written by [toJson].
  factory FlutwireError.fromJson(Map<String, Object?> json) => FlutwireError(
    type: json['type'] as String? ?? 'Error',
    message: json['message'] as String? ?? '',
    stack: json['stack'] as String?,
  );

  /// The runtime type of the exception, such as `SocketException`.
  final String type;

  /// The exception message.
  final String message;

  /// The stack trace, if one was captured.
  final String? stack;

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'type': type,
    'message': message,
    'stack': stack,
  };
}

/// The GraphQL operation a request carried.
@immutable
final class FlutwireGraphql {
  /// Creates a GraphQL description.
  const FlutwireGraphql({this.operationType, this.operationName});

  /// Restores a description written by [toJson].
  factory FlutwireGraphql.fromJson(Map<String, Object?> json) =>
      FlutwireGraphql(
        operationType: json['type'] as String?,
        operationName: json['name'] as String?,
      );

  /// `query`, `mutation` or `subscription`, when it could be read.
  final String? operationType;

  /// The operation name, when the request carried one.
  final String? operationName;

  /// The label shown in a list row.
  String get label =>
      operationName ??
      (operationType == null ? 'GraphQL' : 'anonymous $operationType');

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'type': operationType,
    'name': operationName,
  };
}

/// One HTTP call: what was asked, what came back, and how it went.
///
/// A call is an immutable snapshot. While it is in flight the recorder
/// publishes a new snapshot at each step, with the same [id].
@immutable
final class FlutwireCall {
  /// Creates a call record.
  FlutwireCall({
    required this.id,
    required this.method,
    required this.uri,
    required this.source,
    required this.startedAt,
    required this.request,
    this.state = FlutwireCallState.pending,
    this.firstByteAt,
    this.endedAt,
    this.response,
    this.error,
    this.graphql,
    this.pinned = false,
    this.resentFrom,
    this.messages,
    this.intercept,
  });

  /// Restores a summary written by [toJson]. The bodies come back unloaded.
  factory FlutwireCall.fromJson(Map<String, Object?> json) {
    final req = json['request'] as Map<String, Object?>? ?? const {};
    final res = json['response'] as Map<String, Object?>?;
    return FlutwireCall(
      id: (json['id'] as num).toInt(),
      method: json['method'] as String? ?? 'GET',
      uri: Uri.parse(json['uri'] as String? ?? ''),
      source: FlutwireSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => FlutwireSource.custom,
      ),
      state: FlutwireCallState.values.firstWhere(
        (s) => s.name == json['state'],
        orElse: () => FlutwireCallState.completed,
      ),
      startedAt: DateTime.parse(json['startedAt'] as String),
      firstByteAt: DateTime.tryParse(json['firstByteAt'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
      request: FlutwireRequest(
        headers: FlutwireHeaders.fromJson(req['headers']),
        body: FlutwireBody.fromJson(
          req['body'] as Map<String, Object?>? ?? const {},
        ),
      ),
      response: res == null
          ? null
          : FlutwireResponse(
              statusCode: (res['status'] as num?)?.toInt() ?? 0,
              reasonPhrase: res['reason'] as String? ?? '',
              headers: FlutwireHeaders.fromJson(res['headers']),
              body: FlutwireBody.fromJson(
                res['body'] as Map<String, Object?>? ?? const {},
              ),
              remoteAddress: res['remoteAddress'] as String?,
              remotePort: (res['remotePort'] as num?)?.toInt(),
              certificate: res['certificate'] is Map<String, Object?>
                  ? FlutwireCertificate.fromJson(
                      res['certificate']! as Map<String, Object?>,
                    )
                  : null,
              redirects: [
                for (final r in res['redirects'] as List<Object?>? ?? const [])
                  FlutwireRedirect.fromJson(r! as Map<String, Object?>),
              ],
              compression: res['compression'] as String?,
            ),
      error: json['error'] is Map<String, Object?>
          ? FlutwireError.fromJson(json['error']! as Map<String, Object?>)
          : null,
      graphql: json['graphql'] is Map<String, Object?>
          ? FlutwireGraphql.fromJson(json['graphql']! as Map<String, Object?>)
          : null,
      pinned: json['pinned'] as bool? ?? false,
      resentFrom: (json['resentFrom'] as num?)?.toInt(),
      messages: json['messages'] is Map<String, Object?>
          ? FlutwireMessages.fromJson(json['messages']! as Map<String, Object?>)
          : null,
      intercept: FlutwireIntercept.values.asNameMap()[json['intercept']],
    );
  }

  /// Unique within the history, and increasing with time, so it also orders.
  final int id;

  /// The HTTP method, upper-case.
  final String method;

  /// The URL that was requested, with any redacted query values masked.
  final Uri uri;

  /// Where the call was recorded.
  final FlutwireSource source;

  /// How far the call got.
  final FlutwireCallState state;

  /// When the request was sent.
  final DateTime startedAt;

  /// When the response headers arrived.
  final DateTime? firstByteAt;

  /// When the call finished, failed or was cancelled.
  final DateTime? endedAt;

  /// What the app sent.
  final FlutwireRequest request;

  /// What the server answered, once it has.
  final FlutwireResponse? response;

  /// Why the call failed, if it did.
  final FlutwireError? error;

  /// The GraphQL operation, when the request carried one.
  final FlutwireGraphql? graphql;

  /// Whether the user pinned this call so retention and clearing skip it.
  final bool pinned;

  /// The id of the call this one repeats, when it was sent again from the
  /// inspector. The original may be gone from the history by now.
  final int? resentFrom;

  /// The messages of a WebSocket or of a server-sent event stream, which keep
  /// arriving after the response head. Null for an ordinary call.
  final FlutwireMessages? messages;

  /// How a rule of the user's touched the call, or null when none did.
  final FlutwireIntercept? intercept;

  /// The response status code, or null before one arrived.
  int? get statusCode => response?.statusCode;

  /// The family of [statusCode].
  FlutwireStatusClass get statusClass => FlutwireStatusClass.of(statusCode);

  /// Whether the call is still in flight.
  bool get isPending => state == FlutwireCallState.pending;

  /// Whether the call failed or the server answered with an error status.
  bool get isError =>
      state == FlutwireCallState.failed ||
      (statusCode != null && statusCode! >= 400);

  /// How long the call took, or how long it has been running.
  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  /// The time from sending the request to the first response bytes.
  Duration? get timeToFirstByte => firstByteAt?.difference(startedAt);

  /// The host the call went to.
  String get host => uri.host;

  /// The path and query, which is what a list row shows.
  String get pathAndQuery {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  /// The bytes the app sent in the body.
  int get requestSize => request.body.totalBytes;

  /// The bytes the server sent in the body.
  int get responseSize => response?.body.totalBytes ?? 0;

  /// The method as it goes over the wire. A callable function is listed as
  /// `CALL` but travels as a POST.
  String get wireMethod => source == FlutwireSource.functions ? 'POST' : method;

  /// A lower-case string a free-text search matches against: the method, the
  /// URL, the status, the GraphQL operation, the error and every header field.
  /// Bodies are searched separately, because they may have to be read from
  /// disk.
  late final String searchText = [
    method,
    uri.toString(),
    if (statusCode != null) '$statusCode',
    if (graphql?.operationName != null) graphql!.operationName!,
    if (error != null) error!.message,
    for (final field in request.headers.entries) '${field.key} ${field.value}',
    if (response != null)
      for (final field in response!.headers.entries)
        '${field.key} ${field.value}',
  ].join(' ').toLowerCase();

  /// A copy with the given parts replaced.
  FlutwireCall copyWith({
    int? id,
    Uri? uri,
    FlutwireCallState? state,
    DateTime? firstByteAt,
    DateTime? endedAt,
    FlutwireRequest? request,
    FlutwireResponse? response,
    FlutwireError? error,
    FlutwireGraphql? graphql,
    bool? pinned,
    FlutwireMessages? messages,
    FlutwireIntercept? intercept,
  }) => FlutwireCall(
    id: id ?? this.id,
    method: method,
    uri: uri ?? this.uri,
    source: source,
    startedAt: startedAt,
    state: state ?? this.state,
    firstByteAt: firstByteAt ?? this.firstByteAt,
    endedAt: endedAt ?? this.endedAt,
    request: request ?? this.request,
    response: response ?? this.response,
    error: error ?? this.error,
    graphql: graphql ?? this.graphql,
    pinned: pinned ?? this.pinned,
    resentFrom: resentFrom,
    messages: messages ?? this.messages,
    intercept: intercept ?? this.intercept,
  );

  /// A JSON-encodable summary. Body bytes are not included: the store keeps
  /// them in files of their own.
  Map<String, Object?> toJson() => {
    'v': 1,
    'id': id,
    'method': method,
    'uri': uri.toString(),
    'source': source.name,
    'state': state.name,
    'startedAt': startedAt.toIso8601String(),
    'firstByteAt': firstByteAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'request': {
      'headers': request.headers.toJson(),
      'body': request.body.toJson(),
    },
    if (response case final res?)
      'response': {
        'status': res.statusCode,
        'reason': res.reasonPhrase,
        'headers': res.headers.toJson(),
        'body': res.body.toJson(),
        'remoteAddress': res.remoteAddress,
        'remotePort': res.remotePort,
        'certificate': res.certificate?.toJson(),
        'redirects': [for (final r in res.redirects) r.toJson()],
        'compression': res.compression,
      },
    'error': error?.toJson(),
    'graphql': graphql?.toJson(),
    'pinned': pinned,
    if (resentFrom != null) 'resentFrom': resentFrom,
    if (messages != null) 'messages': messages!.toJson(),
    if (intercept != null) 'intercept': intercept!.name,
  };

  @override
  String toString() =>
      'FlutwireCall(#$id $method $uri ${state.name} $statusCode)';
}
