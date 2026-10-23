import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/graphql.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';

FlutwireGraphql? detect(
  Object? json, {
  String method = 'POST',
  String url = 'https://api.example.com/graphql',
  String type = 'application/json',
  int? total,
  FlutwireHeaders headers = FlutwireHeaders.empty,
  String? raw,
}) {
  final bytes = Uint8List.fromList(utf8.encode(raw ?? jsonEncode(json)));
  return detectGraphql(
    method: method,
    uri: Uri.parse(url),
    headers: headers,
    body: FlutwireBody(bytes: bytes, totalBytes: total, contentType: type),
  );
}

void main() {
  test('reads operationName and the type from the document', () {
    final g = detect({
      'operationName': 'GetUser',
      'query': 'query GetUser(\$id: ID!) { user(id: \$id) { name } }',
      'variables': {'id': '1'},
    });
    expect(g?.operationName, 'GetUser');
    expect(g?.operationType, 'query');
    expect(g?.label, 'GetUser');
  });

  test('falls back to the name declared in the document', () {
    final g = detect({'query': 'mutation AddItem { add { id } }'});
    expect(g?.operationName, 'AddItem');
    expect(g?.operationType, 'mutation');
  });

  test('an anonymous shorthand query is still a query', () {
    final g = detect({'query': '{ viewer { id } }'});
    expect(g?.operationType, 'query');
    expect(g?.operationName, isNull);
    expect(g?.label, 'anonymous query');
  });

  test('a search endpoint with a query field is not GraphQL', () {
    expect(detect({'query': 'running shoes', 'page': 2}), isNull);
  });

  test('batched operations report the first and how many follow', () {
    final g = detect([
      {'operationName': 'A', 'query': 'query A { a }'},
      {'operationName': 'B', 'query': 'query B { b }'},
      {'operationName': 'C', 'query': 'query C { c }'},
    ]);
    expect(g?.operationName, 'A +2');
  });

  test('persisted queries carry a name and no document', () {
    final g = detect({
      'operationName': 'Feed',
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': 'abc'},
      },
    });
    expect(g?.operationName, 'Feed');
  });

  test('reads a raw application/graphql body', () {
    final g = detect(null, raw: 'query Raw { x }', type: 'application/graphql');
    expect(g?.operationName, 'Raw');
  });

  test('reads a GET with the document in the query string', () {
    final g = detectGraphql(
      method: 'GET',
      uri: Uri.parse(
        'https://x.test/g?query=${Uri.encodeQueryComponent('query Q { a }')}&operationName=Named',
      ),
      headers: FlutwireHeaders.empty,
      body: FlutwireBody.empty(),
    );
    expect(g?.operationName, 'Named');
  });

  test('reads the name from a cut body', () {
    final full = jsonEncode({
      'operationName': 'Big',
      'query': 'query Big { a }',
      'variables': {'blob': 'x' * 500},
    });
    final cut = full.substring(0, 80);
    final g = detect(null, raw: cut, total: full.length);
    expect(g?.operationName, 'Big');
  });

  test('falls back to an operation-name header', () {
    final g = detect(
      {'unrelated': true},
      headers: FlutwireHeaders.fromMap({
        'x-apollo-operation-name': 'FromHeader',
      }),
    );
    expect(g?.operationName, 'FromHeader');
  });

  test('a plain JSON POST is not GraphQL', () {
    expect(detect({'name': 'x'}, url: 'https://x.test/items'), isNull);
  });

  test('an empty body is not GraphQL', () {
    expect(
      detectGraphql(
        method: 'POST',
        uri: Uri.parse('https://x.test/graphql'),
        headers: FlutwireHeaders.empty,
        body: FlutwireBody.empty(),
      ),
      isNull,
    );
  });
}
