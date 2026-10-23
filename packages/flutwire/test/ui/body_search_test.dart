import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/ui/inspector/controller.dart';

FlutwireBody json(String text) => FlutwireBody(
  bytes: Uint8List.fromList(utf8.encode(text)),
  contentType: 'application/json',
);

FlutwireCall call(
  int id, {
  String url = 'https://api.test/items',
  String? requestBody,
  String? responseBody,
  Map<String, String> responseHeaders = const {},
  Map<String, String> requestHeaders = const {},
  FlutwireCallState state = FlutwireCallState.completed,
}) {
  final start = DateTime.utc(2026, 10, 23, 12);
  return FlutwireCall(
    id: id,
    method: 'GET',
    uri: Uri.parse(url),
    source: FlutwireSource.io,
    state: state,
    startedAt: start,
    endedAt: state == FlutwireCallState.pending
        ? null
        : start.add(const Duration(milliseconds: 50)),
    request: FlutwireRequest(
      headers: FlutwireHeaders.fromMap(requestHeaders),
      body: requestBody == null ? FlutwireBody.empty() : json(requestBody),
    ),
    response: state == FlutwireCallState.pending
        ? null
        : FlutwireResponse(
            statusCode: 200,
            headers: FlutwireHeaders.fromMap(responseHeaders),
            body: responseBody == null
                ? FlutwireBody.empty()
                : json(responseBody),
          ),
  );
}

void main() {
  late List<FlutwireCall> history;
  late ValueNotifier<List<FlutwireCall>> source;
  late InspectorController controller;
  late List<int> loaded;

  List<int> ids() => [for (final c in controller.visible) c.id];

  Future<void> settle() => pumpEventQueue(times: 200);

  setUp(() {
    history = [
      call(4, responseBody: '{"club":"Orion","members":3}'),
      call(3, requestBody: '{"name":"Vega"}'),
      call(2, responseHeaders: {'x-request-id': 'abc123'}),
      call(1, url: 'https://api.test/clubs', responseBody: '{"club":"Lyra"}'),
    ];
    source = ValueNotifier(history);
    loaded = [];
    controller = InspectorController(
      source,
      loadCall: (id) async {
        loaded.add(id);
        return history.where((c) => c.id == id).firstOrNull;
      },
    );
  });

  tearDown(() {
    controller.dispose();
    source.dispose();
  });

  test('matches the name and the value of a header', () {
    controller.setQuery('abc123');
    expect(ids(), [2]);
    controller.setQuery('X-Request-ID');
    expect(ids(), [2]);
  });

  test('finds text inside a response body', () async {
    controller.setQuery('orion');
    await settle();
    expect(ids(), [4]);
  });

  test('finds text inside a request body', () async {
    controller.setQuery('vega');
    await settle();
    expect(ids(), [3]);
  });

  test(
    'the matches of the URL and of the bodies are listed together',
    () async {
      controller.setQuery('club');
      await settle();
      // 1 matches by its URL, 4 by its body.
      expect(ids(), [4, 1]);
    },
  );

  test('says it is searching while it reads, and stops when done', () async {
    controller.setQuery('orion');
    expect(controller.isSearchingBodies, isTrue);
    await settle();
    expect(controller.isSearchingBodies, isFalse);
  });

  test('does not read bodies for a status prefix or a single letter', () async {
    controller.setQuery('20');
    await settle();
    controller.setQuery('o');
    await settle();
    expect(loaded, isEmpty);
  });

  test('does not read a call the metadata already matched', () async {
    controller.setQuery('abc123');
    await settle();
    expect(loaded, isNot(contains(2)));
  });

  test('a newer search replaces the older one', () async {
    controller.setQuery('orion');
    controller.setQuery('vega');
    await settle();
    expect(ids(), [3]);
  });

  test('clearing the search clears what the bodies matched', () async {
    controller.setQuery('orion');
    await settle();
    controller.clearFilters();
    expect(ids(), [4, 3, 2, 1]);
    expect(controller.isSearchingBodies, isFalse);
  });

  test('reads a running call once it has finished', () async {
    history = [call(5, state: FlutwireCallState.pending), ...history];
    source.value = history;
    controller.setQuery('lyra');
    await settle();
    expect(loaded, isNot(contains(5)));

    history = [
      call(5, responseBody: '{"club":"Lyra Two"}'),
      ...history.skip(1),
    ];
    source.value = history;
    await settle();
    expect(ids(), contains(5));
  });

  test('a call that left the history leaves the matches', () async {
    controller.setQuery('orion');
    await settle();
    source.value = history.where((c) => c.id != 4).toList();
    await settle();
    expect(ids(), isEmpty);
  });

  test('without a loader only the metadata is searched', () async {
    final plain = InspectorController(source);
    addTearDown(plain.dispose);
    plain.setQuery('orion');
    await settle();
    expect(plain.visible, isEmpty);
    expect(plain.isSearchingBodies, isFalse);
  });

  test('a body that cannot be read as text is skipped', () async {
    history = [
      FlutwireCall(
        id: 9,
        method: 'GET',
        uri: Uri.parse('https://cdn.test/a.bin'),
        source: FlutwireSource.io,
        state: FlutwireCallState.completed,
        startedAt: DateTime.utc(2026, 10, 23, 12),
        endedAt: DateTime.utc(2026, 10, 23, 12, 0, 1),
        request: FlutwireRequest(
          headers: FlutwireHeaders.empty,
          body: FlutwireBody.empty(),
        ),
        response: FlutwireResponse(
          statusCode: 200,
          headers: FlutwireHeaders.empty,
          body: FlutwireBody(
            bytes: Uint8List.fromList([0, 1, 2, 255, 254, 0]),
            contentType: 'application/octet-stream',
          ),
        ),
      ),
    ];
    source.value = history;
    controller.setQuery('orion');
    await settle();
    expect(ids(), isEmpty);
  });
}
