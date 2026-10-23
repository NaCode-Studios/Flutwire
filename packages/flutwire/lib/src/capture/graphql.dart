import 'dart:convert';

import '../model/body.dart';
import '../model/call.dart';
import '../model/headers.dart';

final RegExp _operation = RegExp(
  r'^\s*(query|mutation|subscription)\b\s*([A-Za-z_][A-Za-z0-9_]*)?',
);
final RegExp _looksLikeGraphql = RegExp(
  r'^\s*(query|mutation|subscription|fragment)\b|^\s*\{',
);

/// Reads the GraphQL operation a request carries, or null if it is not one.
///
/// A request counts as GraphQL when its payload has a `query` string that
/// reads like a document, which keeps a search endpoint that happens to call
/// its parameter `query` out of the list. The name comes from `operationName`
/// when the client sent one, and from the document otherwise. Batched requests
/// report the first operation and how many follow it.
FlutwireGraphql? detectGraphql({
  required String method,
  required Uri uri,
  required FlutwireHeaders headers,
  required FlutwireBody body,
}) {
  final fromHeader = _fromHeader(headers);

  if (method == 'GET' || method == 'HEAD') {
    final query = uri.queryParameters['query'];
    if (query == null || !_looksLikeGraphql.hasMatch(query)) return null;
    return _describe(query, uri.queryParameters['operationName']);
  }

  if (!body.loaded || body.isEmpty) return fromHeader;

  if (body.mimeType == 'application/graphql') {
    final text = body.text;
    if (text == null || !_looksLikeGraphql.hasMatch(text)) return fromHeader;
    return _describe(text, null);
  }

  if (body.kind != FlutwireBodyKind.json) return fromHeader;

  if (body.isValidJson) {
    final value = body.jsonValue;
    if (value is Map<String, Object?>) {
      return _fromObject(value) ?? fromHeader;
    }
    if (value is List<Object?>) {
      final operations = [
        for (final item in value)
          if (item is Map<String, Object?>) _fromObject(item),
      ].whereType<FlutwireGraphql>().toList();
      if (operations.isEmpty) return fromHeader;
      final first = operations.first;
      if (operations.length == 1) return first;
      final name = first.operationName ?? first.operationType ?? 'batch';
      return FlutwireGraphql(
        operationType: first.operationType,
        operationName: '$name +${operations.length - 1}',
      );
    }
    return fromHeader;
  }

  // A cut body cannot be parsed, but the fields that matter come first.
  return _fromPartialJson(body.text ?? '') ?? fromHeader;
}

FlutwireGraphql? _fromObject(Map<String, Object?> json) {
  final query = json['query'];
  final name = json['operationName'];
  if (query is String && _looksLikeGraphql.hasMatch(query)) {
    return _describe(query, name is String ? name : null);
  }
  // Persisted queries send an id and a name instead of the document.
  final extensions = json['extensions'];
  if (query == null &&
      name is String &&
      extensions is Map<String, Object?> &&
      extensions.containsKey('persistedQuery')) {
    return FlutwireGraphql(operationName: name);
  }
  return null;
}

FlutwireGraphql? _fromPartialJson(String text) {
  final query = RegExp(
    r'"query"\s*:\s*("(?:[^"\\]|\\.)*)',
  ).firstMatch(text)?.group(1);
  if (query == null) return null;
  String document;
  try {
    document = jsonDecode('$query"') as String;
  } on FormatException {
    document = query.substring(1);
  }
  if (!_looksLikeGraphql.hasMatch(document)) return null;
  final name = RegExp(
    r'"operationName"\s*:\s*"((?:[^"\\]|\\.)*)"',
  ).firstMatch(text)?.group(1);
  return _describe(document, name);
}

FlutwireGraphql _describe(String document, String? operationName) {
  final match = _operation.firstMatch(document);
  final type =
      match?.group(1) ?? (document.trimLeft().startsWith('{') ? 'query' : null);
  final declared = match?.group(2);
  final name = (operationName != null && operationName.isNotEmpty)
      ? operationName
      : declared;
  return FlutwireGraphql(operationType: type, operationName: name);
}

FlutwireGraphql? _fromHeader(FlutwireHeaders headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase().contains('operation-name') &&
        entry.value.isNotEmpty) {
      return FlutwireGraphql(operationName: entry.value);
    }
  }
  return null;
}
