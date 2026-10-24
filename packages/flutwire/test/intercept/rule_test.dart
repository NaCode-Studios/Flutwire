import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/rule.dart';

FlutwireRule _breakpoint(String pattern, {String? method}) => FlutwireRule(
  id: 'r1',
  kind: FlutwireRuleKind.breakpoint,
  pattern: pattern,
  method: method,
);

FlutwireMockResponse _answer([int status = 200]) => FlutwireMockResponse(
  statusCode: status,
  body: Uint8List.fromList([1, 2, 3]),
);

void main() {
  group('what a pattern matches', () {
    test('a host and a path, with a star for what varies', () {
      final rule = _breakpoint('api.test/items/*');

      expect(
        rule.matches('GET', Uri.parse('https://api.test/items/9')),
        isTrue,
      );
      expect(rule.matches('GET', Uri.parse('https://api.test/items/')), isTrue);
      expect(rule.matches('GET', Uri.parse('https://api.test/items')), isFalse);
      expect(
        rule.matches('GET', Uri.parse('https://other.test/items/9')),
        isFalse,
      );
    });

    test('whatever the scheme, when the pattern has none', () {
      final rule = _breakpoint('api.test/*');

      expect(rule.matches('GET', Uri.parse('http://api.test/a')), isTrue);
      expect(rule.matches('GET', Uri.parse('https://api.test/a')), isTrue);
    });

    test('the query is part of what is matched', () {
      final rule = _breakpoint('api.test/search?q=*');

      expect(
        rule.matches('GET', Uri.parse('https://api.test/search?q=cats')),
        isTrue,
      );
      expect(
        rule.matches('GET', Uri.parse('https://api.test/search')),
        isFalse,
      );
      expect(
        _breakpoint(
          'api.test/search',
        ).matches('GET', Uri.parse('https://api.test/search?q=cats')),
        isFalse,
      );
    });

    test('a port that was written out is part of the host', () {
      final rule = _breakpoint('localhost:8080/*');

      expect(rule.matches('GET', Uri.parse('http://localhost:8080/a')), isTrue);
      expect(rule.matches('GET', Uri.parse('http://localhost/a')), isFalse);
      expect(rule.matches('GET', Uri.parse('http://localhost:9/a')), isFalse);
    });

    test('a pattern that starts with a scheme is about the whole address', () {
      final rule = _breakpoint('https://api.test/v1/*');

      expect(rule.matches('GET', Uri.parse('https://api.test/v1/a')), isTrue);
      expect(rule.matches('GET', Uri.parse('http://api.test/v1/a')), isFalse);
      expect(
        rule.matches('GET', Uri.parse('https://api.test:444/v1/a')),
        isFalse,
      );
    });

    test('anywhere in the host, with a star at the start', () {
      final rule = _breakpoint('*.test/login');

      expect(rule.matches('POST', Uri.parse('https://api.test/login')), isTrue);
      expect(rule.matches('POST', Uri.parse('https://a.b.test/login')), isTrue);
      expect(
        rule.matches('POST', Uri.parse('https://api.test/logins')),
        isFalse,
      );
    });

    test('whatever the case', () {
      final rule = _breakpoint('API.test/Items/*');

      expect(
        rule.matches('GET', Uri.parse('https://api.TEST/items/1')),
        isTrue,
      );
    });

    test('and treats everything but the star as plain text', () {
      final rule = _breakpoint('api.test/a+b(1)/*');

      expect(
        rule.matches('GET', Uri.parse('https://api.test/a+b(1)/x')),
        isTrue,
      );
      expect(
        rule.matches('GET', Uri.parse('https://api.test/aab1/x')),
        isFalse,
      );
      expect(
        rule.matches('GET', Uri.parse('https://apixtest/a+b(1)/x')),
        isFalse,
      );
    });

    test('a bare star is every request', () {
      expect(
        _breakpoint('*').matches('GET', Uri.parse('https://api.test/a?b=c')),
        isTrue,
      );
    });

    test('an address with no path is the path of a slash', () {
      expect(
        _breakpoint('api.test/').matches('GET', Uri.parse('https://api.test')),
        isTrue,
      );
    });

    test('only the method the rule names', () {
      final rule = _breakpoint('api.test/*', method: 'POST');

      expect(rule.matches('POST', Uri.parse('https://api.test/a')), isTrue);
      expect(rule.matches('post', Uri.parse('https://api.test/a')), isTrue);
      expect(rule.matches('GET', Uri.parse('https://api.test/a')), isFalse);
    });
  });

  group('a rule', () {
    test('is described by its name, or else by what it matches', () {
      expect(_breakpoint('api.test/*').label, 'ANY api.test/*');
      expect(_breakpoint('api.test/*', method: 'PUT').label, 'PUT api.test/*');
      expect(
        FlutwireRule(
          id: 'r',
          kind: FlutwireRuleKind.mock,
          pattern: 'x',
          name: 'Empty cart',
          response: _answer(),
        ).label,
        'Empty cart',
      );
    });

    test('can be changed, and made to take any method again', () {
      final rule = _breakpoint('api.test/*', method: 'POST');

      expect(rule.copyWith(pattern: 'b.test/*').pattern, 'b.test/*');
      expect(rule.copyWith(enabled: false).enabled, isFalse);
      expect(rule.copyWith(method: 'PUT').method, 'PUT');
      expect(rule.copyWith(anyMethod: true).method, isNull);
      expect(rule.copyWith(name: 'x').method, 'POST');
    });

    test('survives being written and read', () {
      final mock = FlutwireRule(
        id: 'r7',
        kind: FlutwireRuleKind.mock,
        pattern: 'api.test/items/*',
        method: 'GET',
        name: 'Items',
        enabled: false,
        response: FlutwireMockResponse(
          statusCode: 503,
          reasonPhrase: 'Busy',
          headers: FlutwireHeaders.fromMap({
            'content-type': 'application/json',
          }),
          body: Uint8List.fromList([0, 255, 10]),
          delay: const Duration(milliseconds: 250),
        ),
      );

      final back = FlutwireRule.fromJson(mock.toJson())!;

      expect(back.id, 'r7');
      expect(back.kind, FlutwireRuleKind.mock);
      expect(back.pattern, 'api.test/items/*');
      expect(back.method, 'GET');
      expect(back.name, 'Items');
      expect(back.enabled, isFalse);
      expect(back.response, mock.response);
    });

    test('a breakpoint has no response to write', () {
      final json = _breakpoint('a/*').toJson();

      expect(json.containsKey('response'), isFalse);
      expect(json.containsKey('method'), isFalse);
      expect(FlutwireRule.fromJson(json)!.kind, FlutwireRuleKind.breakpoint);
    });

    test('is not made of what makes no sense', () {
      expect(FlutwireRule.fromJson('nothing'), isNull);
      expect(FlutwireRule.fromJson(<String, Object?>{}), isNull);
      expect(
        FlutwireRule.fromJson({'id': 'r', 'kind': 'bounce', 'pattern': 'a'}),
        isNull,
      );
      // A mock with no response, and a breakpoint with one.
      expect(
        FlutwireRule.fromJson({'id': 'r', 'kind': 'mock', 'pattern': 'a'}),
        isNull,
      );
      final withResponse = _breakpoint('a').toJson()
        ..['response'] = _answer().toJson();
      expect(FlutwireRule.fromJson(withResponse), isNull);
      expect(
        FlutwireRule.fromJson({
          'id': 'r',
          'kind': 'mock',
          'pattern': 'a',
          'response': {'body': '***not base64***'},
        }),
        isNull,
      );
    });
  });

  group('a mock response', () {
    test('compares by what it holds', () {
      expect(_answer(), _answer());
      expect(_answer().hashCode, _answer().hashCode);
      expect(_answer(), isNot(_answer(404)));
    });

    test('has the answer of a server that is working by default', () {
      final json = FlutwireMockResponse.fromJson(const {});

      expect(json.statusCode, 200);
      expect(json.body, isEmpty);
      expect(json.delay, Duration.zero);
    });
  });
}
