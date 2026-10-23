import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/model/headers.dart';
import 'package:flutwire/src/notify/notifier.dart';
import 'package:flutwire/src/platform/native.dart';
import 'package:flutwire/src/store/store.dart';

const channel = MethodChannel('test/flutwire');

FlutwireCall call(
  int id, {
  String method = 'GET',
  String path = '/items',
  int? status = 200,
  FlutwireCallState state = FlutwireCallState.completed,
  FlutwireGraphql? graphql,
}) {
  final start = DateTime.utc(2026, 10, 23, 12);
  return FlutwireCall(
    id: id,
    method: method,
    uri: Uri.parse('https://api.test$path'),
    source: FlutwireSource.io,
    state: state,
    startedAt: start,
    endedAt: state == FlutwireCallState.pending
        ? null
        : start.add(const Duration(milliseconds: 120)),
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
            body: FlutwireBody(bytes: Uint8List(0)),
          ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> sent;
  late String permission;
  late MemoryFlutwireStore store;
  late ValueNotifier<bool> inspectorOpen;
  late FlutwireNative native;
  late FlutwireNotifier notifier;

  void mockNative({bool present = true}) {
    sent = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          present
              ? (c) async {
                  sent.add(c);
                  switch (c.method) {
                    case 'permission':
                      return permission;
                    case 'requestPermission':
                      permission = 'granted';
                      return permission;
                  }
                  return null;
                }
              : null,
        );
  }

  FlutwireNotifier build({
    FlutwireNotificationConfig config = const FlutwireNotificationConfig(
      throttle: Duration(milliseconds: 40),
    ),
  }) {
    native = FlutwireNative(channel: channel);
    return notifier = FlutwireNotifier(
      native: native,
      store: store,
      config: config,
      inspectorOpen: inspectorOpen,
      locale: () => const Locale('en'),
    );
  }

  List<MethodCall> only(String method) =>
      sent.where((c) => c.method == method).toList();

  Future<void> settle([int ms = 120]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() {
    permission = 'granted';
    store = MemoryFlutwireStore(notifyInterval: Duration.zero);
    inspectorOpen = ValueNotifier(false);
    mockNative();
  });

  tearDown(() async {
    await notifier.dispose();
    await native.dispose();
    await store.dispose();
    inspectorOpen.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('posts nothing while the history is empty', () async {
    build().start();
    await settle();
    expect(only('showSummary'), isEmpty);
  });

  test(
    'lists the newest calls first, with a summary and a clear button',
    () async {
      build().start();
      store
        ..put(call(1, path: '/a'))
        ..put(call(2, method: 'POST', path: '/b', status: 500))
        ..flush();
      await settle();
      final args = only('showSummary').last.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Recording network activity');
      expect(args['lines'], [
        '500 POST api.test/b · 120 ms',
        '200 GET api.test/a · 120 ms',
      ]);
      expect(args['summary'], '2 calls · 1 failed');
      expect(args['count'], 2);
      expect(args['clearLabel'], 'Clear');
    },
  );

  test('lists no more lines than configured', () async {
    build(
      config: const FlutwireNotificationConfig(
        lines: 3,
        throttle: Duration(milliseconds: 40),
      ),
    ).start();
    for (var i = 1; i <= 8; i++) {
      store.put(call(i, path: '/$i'));
    }
    store.flush();
    await settle();
    final args = only('showSummary').last.arguments as Map<Object?, Object?>;
    expect(args['lines'], hasLength(3));
    expect((args['lines']! as List<Object?>).first, contains('/8'));
    expect(args['count'], 8);
  });

  test('folds a burst of calls into a couple of updates', () async {
    build(
      config: const FlutwireNotificationConfig(
        throttle: Duration(milliseconds: 80),
      ),
    ).start();
    for (var i = 1; i <= 50; i++) {
      store.put(call(i));
      store.flush();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await settle(300);
    expect(only('showSummary').length, lessThan(6));
    final args = only('showSummary').last.arguments as Map<Object?, Object?>;
    expect(args['count'], 50, reason: 'the last update has everything');
  });

  test('does not repost a notification that would read the same', () async {
    build().start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    final before = only('showSummary').length;
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('showSummary').length, before);
  });

  test('steps aside while the inspector is open and returns after', () async {
    build().start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('cancelSummary'), isEmpty);

    inspectorOpen.value = true;
    await settle();
    expect(only('cancelSummary'), hasLength(1));

    final posts = only('showSummary').length;
    inspectorOpen.value = false;
    await settle();
    expect(only('showSummary').length, posts + 1);
  });

  test('stays in place while the inspector is open if told to', () async {
    build(
      config: const FlutwireNotificationConfig(
        hideWhileInspectorOpen: false,
        throttle: Duration(milliseconds: 40),
      ),
    ).start();
    store
      ..put(call(1))
      ..flush();
    inspectorOpen.value = true;
    await settle();
    expect(only('cancelSummary'), isEmpty);
  });

  test('asks for permission once, when there is something to show', () async {
    permission = 'notDetermined';
    build().start();
    await settle();
    expect(only('requestPermission'), isEmpty, reason: 'nothing to show yet');
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('requestPermission'), hasLength(1));
    expect(only('showSummary'), isNotEmpty);
  });

  test('does not ask when told not to, and posts nothing', () async {
    permission = 'notDetermined';
    build(
      config: const FlutwireNotificationConfig(
        requestPermission: false,
        throttle: Duration(milliseconds: 40),
      ),
    ).start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('requestPermission'), isEmpty);
    expect(only('showSummary'), isEmpty);
  });

  test('respects a refusal', () async {
    permission = 'denied';
    build().start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('showSummary'), isEmpty);
    expect(only('requestPermission'), isEmpty);
    expect(notifier.permission.value, FlutwireNotificationPermission.denied);
  });

  test('can be disabled outright', () async {
    build(config: const FlutwireNotificationConfig(enabled: false)).start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(only('showSummary'), isEmpty);
  });

  test('copes with a platform that has no native half', () async {
    mockNative(present: false);
    build().start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    expect(native.isMissing, isTrue);
  });

  test('withdraws the notification when it is shut down', () async {
    build().start();
    store
      ..put(call(1))
      ..flush();
    await settle();
    await notifier.dispose();
    expect(only('cancelSummary'), hasLength(1));
  });

  group('callLine', () {
    test('a finished call', () {
      expect(callLine(call(1)), '200 GET api.test/items · 120 ms');
    });
    test('a call in flight has no duration', () {
      expect(
        callLine(call(1, status: null, state: FlutwireCallState.pending)),
        '··· GET api.test/items',
      );
    });
    test('a failed call and a cancelled one', () {
      expect(
        callLine(call(1, status: null, state: FlutwireCallState.failed)),
        'ERR GET api.test/items · 120 ms',
      );
      expect(
        callLine(call(1, status: null, state: FlutwireCallState.cancelled)),
        'CXL GET api.test/items · 120 ms',
      );
    });
    test('a GraphQL call is named by its operation', () {
      expect(
        callLine(
          call(
            1,
            method: 'POST',
            path: '/graphql',
            graphql: const FlutwireGraphql(operationName: 'GetFeed'),
          ),
        ),
        '200 POST GetFeed · 120 ms',
      );
    });
    test('says there is a query without printing it', () {
      expect(
        callLine(call(1, path: '/search?q=secret')),
        '200 GET api.test/search?… · 120 ms',
      );
    });
    test('a long path is shortened', () {
      final line = callLine(call(1, path: '/${'x' * 100}'));
      expect(line, contains('…'));
      expect(line.length, lessThan(80));
    });
  });
}
