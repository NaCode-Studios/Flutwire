import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/breakpoints.dart';
import 'package:flutwire/src/intercept/interception.dart';
import 'package:flutwire/src/intercept/rule.dart';

void main() {
  late FlutwireInterception interception;

  setUp(() => interception = FlutwireInterception(MemoryFlutwirePreferences()));
  tearDown(() => interception.dispose());

  FlutwireRule breakpoint(String pattern) {
    final rule = FlutwireRule(
      id: interception.rules.newId(),
      kind: FlutwireRuleKind.breakpoint,
      pattern: pattern,
    );
    interception.rules.add(rule);
    return rule;
  }

  Future<FlutwireHeldRequest?> hold(FlutwireRule? rule, {String path = '/a'}) =>
      interception.breakpoints
          .hold(
            method: 'GET',
            uri: Uri.parse('https://api.test$path'),
            headers: FlutwireHeaders.empty,
            body: Uint8List(0),
            ruleId: rule?.id,
          )
          .answer;

  group('a breakpoint that holds requests', () {
    test('lets them go as they were when it is switched off', () async {
      final rule = breakpoint('api.test/*');
      final answer = hold(rule);
      expect(interception.breakpoints.held, hasLength(1));

      interception.rules.setEnabled(rule.id, enabled: false);

      final sent = await answer;
      expect(sent?.uri.path, '/a');
      expect(interception.breakpoints.held, isEmpty);
    });

    test('lets them go as they were when it is deleted', () async {
      final rule = breakpoint('api.test/*');
      final answer = hold(rule);

      interception.rules.remove(rule.id);

      expect((await answer)?.uri.path, '/a');
      expect(interception.breakpoints.held, isEmpty);
    });

    test('keeps them while it stays on, whatever else changes', () async {
      final rule = breakpoint('api.test/*');
      final answer = hold(rule);

      breakpoint('other.test/*');
      interception.rules.update(rule.copyWith(name: 'Orders'));

      expect(interception.breakpoints.held, hasLength(1));
      interception.breakpoints.stopAll();
      expect(await answer, isNull);
    });

    test('leaves alone what another breakpoint holds', () async {
      final first = breakpoint('api.test/a');
      final second = breakpoint('api.test/b');
      final released = hold(first, path: '/a');
      final kept = hold(second, path: '/b');

      interception.rules.setEnabled(first.id, enabled: false);

      expect((await released)?.uri.path, '/a');
      expect(interception.breakpoints.held.single.uri.path, '/b');
      interception.breakpoints.stopAll();
      expect(await kept, isNull);
    });

    test('leaves alone a request that names no breakpoint', () async {
      final rule = breakpoint('api.test/*');
      final answer = hold(null);

      interception.rules.setEnabled(rule.id, enabled: false);

      expect(interception.breakpoints.held, hasLength(1));
      interception.breakpoints.stopAll();
      expect(await answer, isNull);
    });
  });

  test('stops what is held when it is disposed', () async {
    final answer = hold(breakpoint('api.test/*'));

    interception.dispose();

    expect(await answer, isNull);
    // The tear-down disposes it once more, which must do no harm.
    interception = FlutwireInterception(MemoryFlutwirePreferences());
  });
}
