import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/intercept/breakpoints.dart';

Future<FlutwireHeldRequest?> _hold(
  FlutwireBreakpoints breakpoints, {
  String path = '/a',
  String? rule,
}) => breakpoints
    .hold(
      method: 'POST',
      uri: Uri.parse('https://api.test$path'),
      headers: FlutwireHeaders.fromMap({'x-id': '1'}),
      body: Uint8List.fromList([1, 2]),
      rule: rule,
    )
    .answer;

/// Lets a held request go as it was held.
void _sendOn(FlutwireBreakpoints breakpoints, int id) =>
    breakpoints.resume(id, breakpoints.find(id)!);

void main() {
  late FlutwireBreakpoints breakpoints;

  setUp(() => breakpoints = FlutwireBreakpoints());
  tearDown(() => breakpoints.dispose());

  test('holds a request until it is let go', () async {
    var released = false;
    final future = _hold(breakpoints).then((request) {
      released = true;
      return request;
    });
    await Future<void>.delayed(Duration.zero);

    expect(breakpoints.held, isNotEmpty);
    expect(released, isFalse);
    final held = breakpoints.held.single;
    expect(held.method, 'POST');
    expect(held.uri.path, '/a');
    expect(held.headers.first('x-id'), '1');
    expect(held.body, [1, 2]);

    _sendOn(breakpoints, held.id);

    final sent = (await future)!;
    expect(sent, same(held));
    expect(breakpoints.held, isEmpty);
  });

  test('lets it go as it was changed', () async {
    final future = _hold(breakpoints);
    final held = breakpoints.held.single;

    breakpoints.resume(
      held.id,
      held.copyWith(
        method: 'PUT',
        uri: Uri.parse('https://staging.test/b'),
        headers: FlutwireHeaders.fromMap({'x-id': '2'}),
        body: Uint8List.fromList([9]),
      ),
    );

    final sent = (await future)!;
    expect(sent.method, 'PUT');
    expect(sent.uri.host, 'staging.test');
    expect(sent.headers.first('x-id'), '2');
    expect(sent.body, [9]);
    expect(sent.id, held.id);
  });

  test('says null when the request is stopped', () async {
    final future = _hold(breakpoints);

    breakpoints.stop(breakpoints.held.single.id);

    expect(await future, isNull);
  });

  test(
    'holds several, the oldest first, and lets each go on its own',
    () async {
      final first = _hold(breakpoints, path: '/first');
      final second = _hold(breakpoints, path: '/second');
      final ids = breakpoints.held.map((r) => r.id).toList();

      expect(breakpoints.held.map((r) => r.uri.path), ['/first', '/second']);
      expect(ids[1], greaterThan(ids[0]));

      breakpoints.stop(ids[1]);
      expect(await second, isNull);
      expect(breakpoints.held.single.uri.path, '/first');
      _sendOn(breakpoints, ids[0]);
      expect((await first)!.uri.path, '/first');
    },
  );

  test(
    'tells its listeners when a request arrives and when it leaves',
    () async {
      var told = 0;
      breakpoints.addListener(() => told++);

      final future = _hold(breakpoints);
      expect(told, 1);
      breakpoints.stop(breakpoints.held.single.id);
      await future;

      expect(told, 2);
    },
  );

  test('calls back with each request as it is held', () async {
    final seen = <FlutwireHeldRequest>[];
    breakpoints.onHeld = seen.add;

    unawaited(_hold(breakpoints, rule: 'Login'));

    expect(seen.single.rule, 'Login');
    expect(seen.single.id, breakpoints.held.single.id);
  });

  test('gives the ticket the number the request is held under', () async {
    final ticket = breakpoints.hold(
      method: 'GET',
      uri: Uri.parse('https://api.test/a'),
      headers: FlutwireHeaders.empty,
      body: Uint8List(0),
    );

    expect(ticket.id, breakpoints.held.single.id);
    breakpoints.stop(ticket.id);
    expect(await ticket.answer, isNull);
  });

  test('finds a held request by its id', () async {
    unawaited(_hold(breakpoints));
    final held = breakpoints.held.single;

    expect(breakpoints.find(held.id), held);
    expect(breakpoints.find(999), isNull);
  });

  test('does nothing when told to let go of a request it does not hold', () {
    var told = 0;
    breakpoints.addListener(() => told++);

    breakpoints
      ..stop(42)
      ..resume(
        42,
        FlutwireHeldRequest(
          id: 42,
          method: 'GET',
          uri: Uri.parse('https://api.test/x'),
          headers: FlutwireHeaders.empty,
          body: Uint8List(0),
          since: DateTime(2026),
        ),
      );

    expect(told, 0);
  });

  test('stops everything it holds, so that no call is left waiting', () async {
    final a = _hold(breakpoints);
    final b = _hold(breakpoints);

    breakpoints.stopAll();

    expect(await a, isNull);
    expect(await b, isNull);
    expect(breakpoints.held, isEmpty);
  });

  test(
    'stops what it holds when it is disposed, and holds nothing after',
    () async {
      final pending = _hold(breakpoints);
      breakpoints.dispose();

      expect(await pending, isNull);
      expect(await _hold(breakpoints), isNull);
      expect(breakpoints.held, isEmpty);
      // The tear-down disposes it again.
      breakpoints = FlutwireBreakpoints();
    },
  );
}
