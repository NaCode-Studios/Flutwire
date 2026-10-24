import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/rule.dart';
import 'package:flutwire/src/intercept/rules.dart';

FlutwireRule _mock(FlutwireRules rules, String pattern, {String? method}) =>
    FlutwireRule(
      id: rules.newId(),
      kind: FlutwireRuleKind.mock,
      pattern: pattern,
      method: method,
      response: FlutwireMockResponse(statusCode: 200, body: Uint8List(0)),
    );

FlutwireRule _breakpoint(FlutwireRules rules, String pattern) => FlutwireRule(
  id: rules.newId(),
  kind: FlutwireRuleKind.breakpoint,
  pattern: pattern,
);

final _items = Uri.parse('https://api.test/items/1');

void main() {
  group('the rules in force', () {
    test('answer for a request, by the first that matches', () {
      final rules = FlutwireRules();
      final broad = _mock(rules, 'api.test/*');
      final narrow = _mock(rules, 'api.test/items/*');
      rules.add(broad);
      rules.add(narrow);

      // The newest comes first, so the narrow one made later wins.
      expect(rules.all.map((r) => r.id), [narrow.id, broad.id]);
      expect(rules.mockFor('GET', _items)!.id, narrow.id);
      expect(
        rules.mockFor('GET', Uri.parse('https://api.test/users'))!.id,
        broad.id,
      );
    });

    test('keep mocks and breakpoints apart', () {
      final rules = FlutwireRules();
      rules.add(_breakpoint(rules, 'api.test/*'));

      expect(rules.mockFor('GET', _items), isNull);
      expect(rules.breakpointFor('GET', _items), isNotNull);
    });

    test('leave out a rule that is off', () {
      final rules = FlutwireRules();
      final rule = _mock(rules, 'api.test/*');
      rules.add(rule);

      rules.setEnabled(rule.id, enabled: false);
      expect(rules.mockFor('GET', _items), isNull);
      expect(rules.activeCount, 0);

      rules.setEnabled(rule.id, enabled: true);
      expect(rules.mockFor('GET', _items), isNotNull);
      expect(rules.activeCount, 1);
    });

    test('look at the method too', () {
      final rules = FlutwireRules();
      rules.add(_mock(rules, 'api.test/*', method: 'POST'));

      expect(rules.mockFor('GET', _items), isNull);
      expect(rules.mockFor('POST', _items), isNotNull);
    });
  });

  group('the list of rules', () {
    test('gives every rule an id of its own', () {
      final rules = FlutwireRules();

      expect({for (var i = 0; i < 50; i++) rules.newId()}, hasLength(50));
    });

    test('is changed, and says so', () {
      final rules = FlutwireRules();
      var told = 0;
      rules.addListener(() => told++);
      final rule = _mock(rules, 'a/*');

      rules.add(rule);
      rules.update(rule.copyWith(name: 'A'));
      rules.setEnabled(rule.id, enabled: false);
      rules.remove(rule.id);

      expect(told, 4);
      expect(rules.all, isEmpty);
    });

    test('says nothing for what changes nothing', () {
      final rules = FlutwireRules();
      final rule = _mock(rules, 'a/*');
      rules.add(rule);
      var told = 0;
      rules.addListener(() => told++);

      rules.setEnabled(rule.id, enabled: true);
      rules.remove('unknown');
      rules.update(_mock(rules, 'b/*'));

      expect(told, 0);
    });

    test('finds a rule by its id', () {
      final rules = FlutwireRules();
      final rule = _mock(rules, 'a/*');
      rules.add(rule);

      expect(rules.find(rule.id), same(rule));
      expect(rules.find('nope'), isNull);
    });
  });

  group('the rules that are kept', () {
    test('are there the next time the app runs', () {
      final preferences = MemoryFlutwirePreferences();
      final first = FlutwireRules(preferences);
      first.add(_mock(first, 'api.test/*', method: 'GET'));
      first.add(_breakpoint(first, 'api.test/login'));
      final older = first.all.last;

      final second = FlutwireRules(preferences);

      expect(second.all.map((r) => r.id), first.all.map((r) => r.id));
      expect(second.all.last.id, older.id);
      expect(second.all.last.response, older.response);
      expect(second.all.first.kind, FlutwireRuleKind.breakpoint);
    });

    test('are forgotten when the last one goes', () {
      final preferences = MemoryFlutwirePreferences();
      final rules = FlutwireRules(preferences);
      final rule = _mock(rules, 'a/*');
      rules.add(rule);
      expect(preferences.read('rules'), isNotNull);

      rules.remove(rule.id);

      expect(preferences.read('rules'), isNull);
    });

    test('are read as far as they can be', () {
      final good = FlutwireRule(
        id: 'good',
        kind: FlutwireRuleKind.breakpoint,
        pattern: 'a/*',
      );
      final preferences = MemoryFlutwirePreferences({
        'rules': jsonEncode([
          good.toJson(),
          'junk',
          {'id': 'x'},
        ]),
      });

      expect(FlutwireRules(preferences).all.map((r) => r.id), ['good']);
    });

    test('are none when what was kept is not even JSON', () {
      final preferences = MemoryFlutwirePreferences({'rules': '{{{'});

      expect(FlutwireRules(preferences).all, isEmpty);
      expect(
        FlutwireRules(MemoryFlutwirePreferences({'rules': '"text"'})).all,
        isEmpty,
      );
    });
  });
}
