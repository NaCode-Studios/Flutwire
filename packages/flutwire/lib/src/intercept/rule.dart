import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../model/headers.dart';

/// The header fields of a stored response that are left out when it is served.
/// The body is served as it is stored, decompressed, so what the server once
/// said about its length and its encoding no longer holds.
const Set<String> servedHeadersLeftOut = {
  'content-length',
  'transfer-encoding',
  'content-encoding',
};

/// What a rule does with a request it matches.
enum FlutwireRuleKind {
  /// Answers the request with a stored response, and sends nothing.
  mock,

  /// Holds the request until it has been looked at and, if need be, changed.
  breakpoint,
}

/// The answer a mock rule gives.
@immutable
final class FlutwireMockResponse {
  /// Creates an answer.
  const FlutwireMockResponse({
    required this.statusCode,
    required this.body,
    this.reasonPhrase = '',
    this.headers = FlutwireHeaders.empty,
    this.delay = Duration.zero,
  });

  /// Restores an answer written by [toJson].
  factory FlutwireMockResponse.fromJson(Map<String, Object?> json) =>
      FlutwireMockResponse(
        statusCode: (json['status'] as num?)?.toInt() ?? 200,
        reasonPhrase: json['reason'] as String? ?? '',
        headers: FlutwireHeaders.fromJson(json['headers']),
        body: base64Decode(json['body'] as String? ?? ''),
        delay: Duration(milliseconds: (json['delay'] as num?)?.toInt() ?? 0),
      );

  /// The status code the app gets.
  final int statusCode;

  /// The reason phrase the app gets, or nothing for the standard one.
  final String reasonPhrase;

  /// The header fields the app gets.
  final FlutwireHeaders headers;

  /// The body the app gets.
  final Uint8List body;

  /// How long to wait before answering, to make a server seem slow.
  final Duration delay;

  /// A copy with the given parts replaced.
  FlutwireMockResponse copyWith({
    int? statusCode,
    String? reasonPhrase,
    FlutwireHeaders? headers,
    Uint8List? body,
    Duration? delay,
  }) => FlutwireMockResponse(
    statusCode: statusCode ?? this.statusCode,
    reasonPhrase: reasonPhrase ?? this.reasonPhrase,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    delay: delay ?? this.delay,
  );

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'status': statusCode,
    'reason': reasonPhrase,
    'headers': headers.toJson(),
    'body': base64Encode(body),
    'delay': delay.inMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is FlutwireMockResponse &&
      other.statusCode == statusCode &&
      other.reasonPhrase == reasonPhrase &&
      other.headers == headers &&
      other.delay == delay &&
      listEquals(other.body, body);

  @override
  int get hashCode => Object.hash(
    statusCode,
    reasonPhrase,
    headers,
    delay,
    Object.hashAll(body),
  );
}

/// A rule that answers a request or holds it, by what the request looks like.
@immutable
final class FlutwireRule {
  /// Creates a rule.
  FlutwireRule({
    required this.id,
    required this.kind,
    required this.pattern,
    this.method,
    this.name = '',
    this.enabled = true,
    this.response,
  }) : assert(
         (kind == FlutwireRuleKind.mock) == (response != null),
         'A mock has a response and a breakpoint has none.',
       );

  /// Restores a rule written by [toJson], or returns null when it makes no
  /// sense.
  static FlutwireRule? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final kind = FlutwireRuleKind.values.asNameMap()[json['kind']];
    final id = json['id'];
    final pattern = json['pattern'];
    if (kind == null || id is! String || pattern is! String) return null;
    final response = json['response'];
    if ((kind == FlutwireRuleKind.mock) != (response is Map<String, Object?>)) {
      return null;
    }
    try {
      return FlutwireRule(
        id: id,
        kind: kind,
        pattern: pattern,
        method: json['method'] as String?,
        name: json['name'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        response: response is Map<String, Object?>
            ? FlutwireMockResponse.fromJson(response)
            : null,
      );
    } on Object {
      return null;
    }
  }

  /// Names the rule within the list of rules.
  final String id;

  /// What the rule does.
  final FlutwireRuleKind kind;

  /// What a request has to look like, written with `*` for any run of
  /// characters: `api.test/items/*`, `*/login`, or `https://api.test/v1/*`.
  ///
  /// A pattern with no scheme is matched against the host, a port that was
  /// written out, the path and the query. One that starts with a scheme is
  /// matched against the whole address. Case does not matter.
  final String pattern;

  /// The method a request has to have, in upper case, or null for any.
  final String? method;

  /// What the rule is called in the list. Empty means it is described by what
  /// it matches.
  final String name;

  /// Whether the rule is in force.
  final bool enabled;

  /// The answer, for a mock.
  final FlutwireMockResponse? response;

  late final RegExp _regex = _compile(pattern);

  /// Whether the pattern names the whole address, scheme included.
  bool get _wholeAddress => pattern.contains('://');

  /// Whether a request with [requestMethod] to [uri] is one this rule is
  /// about. It does not look at [enabled].
  bool matches(String requestMethod, Uri uri) {
    final wanted = method;
    if (wanted != null && wanted != requestMethod.toUpperCase()) return false;
    return _regex.hasMatch(_wholeAddress ? _address(uri) : _target(uri));
  }

  /// The label shown for the rule: its name, or what it matches.
  String get label => name.isNotEmpty ? name : '${method ?? 'ANY'} $pattern';

  /// A copy with the given parts replaced. [method] can be set to null by
  /// passing [anyMethod].
  FlutwireRule copyWith({
    String? pattern,
    String? method,
    bool anyMethod = false,
    String? name,
    bool? enabled,
    FlutwireMockResponse? response,
  }) => FlutwireRule(
    id: id,
    kind: kind,
    pattern: pattern ?? this.pattern,
    method: anyMethod ? null : method ?? this.method,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    response: response ?? this.response,
  );

  /// A JSON-encodable form.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'pattern': pattern,
    'method': ?method,
    'name': name,
    'enabled': enabled,
    'response': ?response?.toJson(),
  };

  /// The host, a port that was written, the path and the query of [uri].
  static String _target(Uri uri) {
    final port = uri.hasPort && uri.port != 0 ? ':${uri.port}' : '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$port$path${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  /// The address without its fragment, which a request never carries.
  static String _address(Uri uri) => uri.removeFragment().toString();

  static RegExp _compile(String pattern) {
    final source = pattern.trim().split('*').map(RegExp.escape).join('.*');
    return RegExp('^$source\$', caseSensitive: false, dotAll: true);
  }
}
