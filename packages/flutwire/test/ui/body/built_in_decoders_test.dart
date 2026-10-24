import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/ui/detail/body_pane.dart';

import '../fake_session.dart';
import '../harness.dart';
import 'helpers.dart';

/// `{"compact": true, "schema": 0}`, in MessagePack.
final List<int> msgpack = [
  0x82,
  0xa7,
  ...'compact'.codeUnits,
  0xc3,
  0xa6,
  ...'schema'.codeUnits,
  0x00,
];

class _Custom implements FlutwireBodyDecoder {
  @override
  String get name => 'Custom';

  @override
  String? decode(
    FlutwireCall call,
    FlutwireBody body, {
    required bool isRequest,
  }) => 'the app read this one';
}

Future<void> show(
  WidgetTester tester,
  FlutwireBody body, {
  List<FlutwireBodyDecoder> decoders = const [],
}) async {
  await pumpFlutwire(
    tester,
    BodyPane(call: testCall(), body: body, isRequest: false),
    session: FakeSession(
      config: FlutwireConfig(
        enabled: true,
        captureDartIo: false,
        persist: false,
        shortcut: false,
        locale: const Locale('en'),
        decoders: decoders,
        notification: const FlutwireNotificationConfig(enabled: false),
      ),
    ),
    size: const Size(420, 900),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('the decoders every inspector has', () {
    testWidgets('read a MessagePack body with no setup', (tester) async {
      await show(tester, bytesBody(msgpack, type: 'application/msgpack'));

      expect(find.textContaining('MessagePack'), findsWidgets);
      expect(find.textContaining('"compact": true'), findsOneWidget);
    });

    testWidgets('read a Protobuf body by field number with no setup', (
      tester,
    ) async {
      final proto = Uint8List.fromList([
        0x0a,
        0x03,
        ...'Ada'.codeUnits,
        0x10,
        0x2a,
      ]);

      await show(tester, bytesBody(proto, type: 'application/x-protobuf'));

      expect(find.textContaining('Protobuf (no schema)'), findsWidgets);
      expect(find.textContaining('"1": "Ada"'), findsOneWidget);
      expect(find.textContaining('"2": 42'), findsOneWidget);
    });

    testWidgets('leave a body of another type as it was', (tester) async {
      await show(tester, bytesBody(msgpack, type: 'application/octet-stream'));

      expect(find.textContaining('MessagePack'), findsNothing);
    });

    testWidgets('come after the ones the app registered', (tester) async {
      await show(
        tester,
        bytesBody(msgpack, type: 'application/msgpack'),
        decoders: [_Custom()],
      );

      expect(find.textContaining('the app read this one'), findsOneWidget);
      expect(find.textContaining('"compact": true'), findsNothing);
    });
  });
}
