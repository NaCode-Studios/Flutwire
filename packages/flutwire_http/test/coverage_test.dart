import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_http/flutwire_http.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:http/testing.dart';

final _uri = Uri.parse('https://api.test/a');

Future<void> start() => Flutwire.init(
  config: const FlutwireConfig(
    enabled: true,
    persist: false,
    captureDartIo: true,
    notification: FlutwireNotificationConfig(enabled: false),
  ),
);

/// A client that never touches dart:io, as `cronet_http` and `cupertino_http`
/// do not.
MockClient offTheWire({bool fails = false}) => MockClient((request) async {
  if (fails) throw ClientException('no route', request.url);
  return Response('{}', 200);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await Flutwire.reset();
    HttpOverrides.global = null;
  });

  group('a client that does not go through dart:io', () {
    test('is named in a note, because nothing records its calls', () async {
      await start();
      final client = FlutwireClient(offTheWire());

      await client.get(_uri);

      final note = Flutwire.coverage.value.single;
      expect(note.gap, FlutwireGap.clientBypassesDartIo);
      expect(note.subject, 'FlutwireClient over MockClient · api.test');
      expect(Flutwire.calls.value, isEmpty);
    });

    test('is named in the note when the call fails too', () async {
      await start();
      final client = FlutwireClient(offTheWire(fails: true));

      await expectLater(client.get(_uri), throwsA(isA<ClientException>()));

      expect(
        Flutwire.coverage.value.single.gap,
        FlutwireGap.clientBypassesDartIo,
      );
    });

    test('is no problem when it is told to record by itself', () async {
      await start();
      final client = FlutwireClient(offTheWire(), force: true);

      await client.get(_uri);

      expect(Flutwire.coverage.value, isEmpty);
      expect(Flutwire.calls.value, hasLength(1));
    });
  });

  test('a client that does go through dart:io leaves no note', () async {
    await start();
    final client = FlutwireClient(IOClient());

    try {
      await client.get(_uri);
    } on Object {
      // The test binding refuses to connect, which does not matter here: the
      // capture saw the call before the refusal.
    }

    expect(Flutwire.coverage.value, isEmpty);
  });

  test(
    'without the capture the adapter records and there is no note',
    () async {
      await Flutwire.init(
        config: const FlutwireConfig(
          enabled: true,
          persist: false,
          captureDartIo: false,
          notification: FlutwireNotificationConfig(enabled: false),
        ),
      );
      final client = FlutwireClient(offTheWire());

      await client.get(_uri);

      expect(Flutwire.coverage.value, isEmpty);
      expect(Flutwire.calls.value, hasLength(1));
    },
  );
}
