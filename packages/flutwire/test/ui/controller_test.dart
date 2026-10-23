import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/ui/inspector/controller.dart';

FlutwireCall call(
  int id, {
  String method = 'GET',
  String url = 'https://api.test/items',
  int? status = 200,
  FlutwireCallState state = FlutwireCallState.completed,
  int millis = 100,
  int bytes = 0,
  bool pinned = false,
  FlutwireGraphql? graphql,
}) {
  final start = DateTime.utc(2026, 10, 23, 12);
  return FlutwireCall(
    id: id,
    method: method,
    uri: Uri.parse(url),
    source: FlutwireSource.io,
    state: state,
    startedAt: start,
    endedAt: state == FlutwireCallState.pending
        ? null
        : start.add(Duration(milliseconds: millis)),
    pinned: pinned,
    graphql: graphql,
    request: FlutwireRequest(
      headers: FlutwireHeaders.empty,
      body: FlutwireBody(bytes: Uint8List(0)),
    ),
    response: status == null
        ? null
        : FlutwireResponse(
            statusCode: status,
            headers: FlutwireHeaders.empty,
            body: FlutwireBody(bytes: Uint8List(0), totalBytes: bytes),
          ),
  );
}

void main() {
  late ValueNotifier<List<FlutwireCall>> source;
  late InspectorController controller;

  List<int> ids() => [for (final c in controller.visible) c.id];

  setUp(() {
    source = ValueNotifier([
      call(
        6,
        method: 'POST',
        url: 'https://api.test/login',
        status: 401,
        millis: 90,
        bytes: 40,
      ),
      call(
        5,
        url: 'https://cdn.test/logo.png',
        status: 304,
        millis: 20,
        bytes: 0,
      ),
      call(
        4,
        method: 'DELETE',
        url: 'https://api.test/items/9',
        status: 500,
        millis: 3000,
        bytes: 10,
      ),
      call(
        3,
        method: 'OPTIONS',
        url: 'https://api.test/items',
        status: 204,
        millis: 15,
      ),
      call(
        2,
        url: 'https://api.test/never',
        status: null,
        state: FlutwireCallState.failed,
        millis: 5000,
      ),
      call(
        1,
        method: 'POST',
        url: 'https://api.test/graphql',
        millis: 300,
        bytes: 9000,
        pinned: true,
        graphql: const FlutwireGraphql(operationName: 'GetFeed'),
      ),
    ]);
    controller = InspectorController(source);
  });

  tearDown(() {
    controller.dispose();
    source.dispose();
  });

  test('lists everything newest first to begin with', () {
    expect(ids(), [6, 5, 4, 3, 2, 1]);
    expect(controller.hasFilters, isFalse);
  });

  group('search', () {
    test('matches the URL, case-insensitively', () {
      controller.setQuery('LOGIN');
      expect(ids(), [6]);
    });

    test('matches a GraphQL operation name', () {
      controller.setQuery('getfeed');
      expect(ids(), [1]);
    });

    test(
      'a few digits are a status code prefix, not a substring of the URL',
      () {
        controller.setQuery('40');
        expect(ids(), [6]);
        controller.setQuery('5');
        expect(ids(), [4]);
      },
    );

    test('more than three digits are text', () {
      controller.setQuery('1234');
      expect(ids(), isEmpty);
    });

    test('ignores surrounding space', () {
      controller.setQuery('  login ');
      expect(ids(), [6]);
    });
  });

  group('filters', () {
    test('by method, with every other method grouped', () {
      controller.toggleMethod('POST');
      expect(ids(), [6, 1]);
      controller.toggleMethod(other);
      expect(ids(), [6, 3, 1]);
    });

    test('by state, adding up inside the group', () {
      controller.toggleState(StateFilter.clientError);
      controller.toggleState(StateFilter.serverError);
      expect(ids(), [6, 4]);
    });

    test('failed, pinned and success', () {
      controller.toggleState(StateFilter.failed);
      expect(ids(), [2]);
      controller.toggleState(StateFilter.failed);
      controller.toggleState(StateFilter.pinned);
      expect(ids(), [1]);
      controller.toggleState(StateFilter.pinned);
      controller.toggleState(StateFilter.success);
      expect(ids(), [3, 1]);
    });

    test('different groups narrow each other', () {
      controller.toggleMethod('POST');
      controller.toggleState(StateFilter.success);
      expect(ids(), [1]);
    });

    test('a running call matches running', () {
      source.value = [
        call(7, status: null, state: FlutwireCallState.pending),
        ...source.value,
      ];
      controller.toggleState(StateFilter.running);
      expect(ids(), [7]);
    });

    test('clearing removes the search and every filter', () {
      controller
        ..setQuery('api')
        ..toggleMethod('GET')
        ..toggleState(StateFilter.success);
      expect(controller.hasFilters, isTrue);
      controller.clearFilters();
      expect(ids(), [6, 5, 4, 3, 2, 1]);
      expect(controller.hasFilters, isFalse);
    });
  });

  group('order', () {
    test('slowest first', () {
      controller.setSort(InspectorSort.slowest);
      expect(ids().take(3), [2, 4, 1]);
    });

    test('largest first', () {
      controller.setSort(InspectorSort.largest);
      expect(ids().take(3), [1, 6, 4]);
    });
  });

  group('selection', () {
    test('toggling and selecting everything that is visible', () {
      controller.toggleSelected(5);
      expect(controller.isSelecting, isTrue);
      expect(controller.selection, {5});
      controller.setQuery('api');
      controller.selectAllVisible();
      expect(controller.selection, {6, 4, 3, 2, 1});
      controller.clearSelection();
      expect(controller.isSelecting, isFalse);
    });

    test('a call that left the history leaves the selection', () {
      controller.toggleSelected(5);
      controller.toggleSelected(6);
      source.value = [
        for (final c in source.value)
          if (c.id != 5) c,
      ];
      expect(controller.selection, {6});
      expect([for (final c in controller.selectedCalls) c.id], [6]);
    });
  });

  test('follows the history as it changes', () {
    var notified = 0;
    controller.addListener(() => notified++);
    source.value = [call(7), ...source.value];
    expect(notified, 1);
    expect(ids().first, 7);
  });
}
