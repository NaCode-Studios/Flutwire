import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/config.dart';
import 'package:flutwire/src/l10n/strings_it.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/model/call.dart';
import 'package:flutwire/src/ui/body/body_viewer.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

import '../harness.dart';
import 'helpers.dart';

Finder chip(String mode) => find.byKey(ValueKey('flutwire.body.mode.$mode'));
Finder content(String mode) =>
    find.byKey(ValueKey('flutwire.body.content.$mode'));

/// The modes on offer, in reading order: row by row, left to right.
List<String> chipNames(WidgetTester tester) {
  final found = <String, Offset>{
    for (final mode in [
      'decoded',
      'tree',
      'pretty',
      'raw',
      'hex',
      'fields',
      'parts',
      'preview',
    ])
      if (chip(mode).evaluate().isNotEmpty) mode: tester.getTopLeft(chip(mode)),
  };
  return found.keys.toList()..sort((a, b) {
    final byRow = found[a]!.dy.compareTo(found[b]!.dy);
    return byRow != 0 ? byRow : found[a]!.dx.compareTo(found[b]!.dx);
  });
}

bool chipEnabled(WidgetTester tester, String mode) =>
    tester
        .widget<InkWell>(
          find.descendant(of: chip(mode), matching: find.byType(InkWell)),
        )
        .onTap !=
    null;

class _Decoder implements FlutwireBodyDecoder {
  _Decoder(this.name, this.result, {this.throws = false});

  @override
  final String name;
  final String? result;
  final bool throws;
  int calls = 0;

  @override
  String? decode(
    FlutwireCall call,
    FlutwireBody body, {
    required bool isRequest,
  }) {
    calls++;
    if (throws) throw StateError('the decoder broke');
    return result;
  }
}

void main() {
  group('the modes of each kind of body', () {
    testWidgets('valid JSON offers tree, pretty and raw, and opens the tree', (
      tester,
    ) async {
      await pumpViewer(tester, jsonBody('{"a":1}'));
      expect(chipNames(tester), ['tree', 'pretty', 'raw']);
      expect(content('tree'), findsOneWidget);
    });

    testWidgets('a cut JSON body opens raw, with the tree and pretty off', (
      tester,
    ) async {
      await pumpViewer(tester, jsonBody('{"a":1,"b":[1,2', total: 5000));
      expect(chipNames(tester), ['tree', 'pretty', 'raw']);
      expect(content('raw'), findsOneWidget);
      expect(chipEnabled(tester, 'tree'), isFalse);
      expect(chipEnabled(tester, 'pretty'), isFalse);
      expect(chipEnabled(tester, 'raw'), isTrue);
      // Tapping a chip that is off changes nothing.
      await tester.tap(chip('tree'));
      await tester.pump();
      expect(content('raw'), findsOneWidget);
    });

    testWidgets('malformed JSON opens raw as well', (tester) async {
      await pumpViewer(tester, jsonBody('{"a": oops}'));
      expect(content('raw'), findsOneWidget);
    });

    testWidgets('XML offers pretty and raw, and opens pretty', (tester) async {
      await pumpViewer(
        tester,
        textBody('<a><b>1</b></a>', type: 'application/xml'),
      );
      expect(chipNames(tester), ['pretty', 'raw']);
      expect(content('pretty'), findsOneWidget);
    });

    testWidgets('HTML and plain text offer raw only', (tester) async {
      await pumpViewer(tester, textBody('<html></html>', type: 'text/html'));
      expect(chipNames(tester), ['raw']);
      await pumpViewer(tester, textBody('hello', type: 'text/plain'));
      expect(chipNames(tester), ['raw']);
    });

    testWidgets('a form offers fields and raw, and opens the fields', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        textBody('a=1&b=2', type: 'application/x-www-form-urlencoded'),
      );
      expect(chipNames(tester), ['fields', 'raw']);
      expect(content('fields'), findsOneWidget);
    });

    testWidgets('a multipart body offers parts and hex, and opens the parts', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        multipartBody([
          '--b',
          'Content-Disposition: form-data; name="x"',
          '',
          'v',
          '--b--',
        ]),
      );
      expect(chipNames(tester), ['parts', 'hex']);
      expect(content('parts'), findsOneWidget);
    });

    testWidgets('an image offers a preview and hex, and opens the preview', (
      tester,
    ) async {
      await pumpViewer(tester, bytesBody(onePixelPng, type: 'image/png'));
      expect(chipNames(tester), ['preview', 'hex']);
      expect(content('preview'), findsOneWidget);
    });

    testWidgets('binary data offers hex only', (tester) async {
      await pumpViewer(
        tester,
        bytesBody([0x1F, 0x8B, 8, 0, 1, 2, 3], type: 'application/gzip'),
      );
      expect(chipNames(tester), ['hex']);
      expect(content('hex'), findsOneWidget);
    });

    testWidgets('switching modes shows the other view', (tester) async {
      await pumpViewer(tester, jsonBody('{"a":1}'));
      await tester.tap(chip('raw'));
      await tester.pump();
      expect(content('raw'), findsOneWidget);
      expect(content('tree'), findsNothing);
      await tester.tap(chip('pretty'));
      await tester.pump();
      expect(content('pretty'), findsOneWidget);
    });
  });

  group('the states without content', () {
    testWidgets('an empty body says so and has no toolbar', (tester) async {
      await pumpViewer(tester, FlutwireBody.empty());
      expect(find.text('No body'), findsOneWidget);
      expect(chipNames(tester), isEmpty);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('a body that is not loaded says so', (tester) async {
      await pumpViewer(
        tester,
        FlutwireBody.unloaded(totalBytes: 4000, contentType: 'text/plain'),
      );
      expect(
        find.text('The body could not be read from the history'),
        findsOneWidget,
      );
    });
  });

  group('the banners', () {
    testWidgets('a cut body says how much was kept', (tester) async {
      await pumpViewer(tester, jsonBody('{"a":1,"b":[1,2', total: 5000));
      expect(find.text('Showing the first 15 B of 4.9 KB'), findsOneWidget);
    });

    testWidgets('a whole body has no truncation banner', (tester) async {
      await pumpViewer(tester, jsonBody('{"a":1}'));
      expect(find.textContaining('Showing the first'), findsNothing);
    });

    testWidgets('the banner follows the language of the inspector', (
      tester,
    ) async {
      await pumpFlutwire(
        tester,
        FlutwireBodyViewer(
          call: testCall(),
          body: jsonBody('{"a":1,', total: 2048),
          isRequest: false,
        ),
        strings: const FlutwireStringsIt(),
      );
      expect(find.text('Mostra i primi 7 B di 2.0 KB'), findsOneWidget);
    });

    testWidgets('the truncation banner stays in every mode', (tester) async {
      await pumpViewer(tester, bytesBody([0x1F, 0x8B, 8, 0], total: 900));
      expect(find.textContaining('Showing the first 4 B'), findsOneWidget);
    });
  });

  group('decoders', () {
    testWidgets('a decoded body opens in its own mode with a banner', (
      tester,
    ) async {
      final decoder = _Decoder('Protobuf', 'field 1: hello');
      await pumpViewer(
        tester,
        bytesBody([0x0A, 0x05, 0x68], type: 'application/x-protobuf'),
        decoders: [decoder],
      );
      expect(chipNames(tester), ['decoded', 'hex']);
      expect(content('decoded'), findsOneWidget);
      expect(find.text('Decoded'), findsOneWidget);
      expect(find.text('Decoded as Protobuf'), findsOneWidget);
      expect(find.textContaining('field 1: hello'), findsOneWidget);
    });

    testWidgets('the link toggles between the raw and the decoded view', (
      tester,
    ) async {
      final decoder = _Decoder('Protobuf', 'field 1: hello');
      await pumpViewer(
        tester,
        bytesBody([0x0A, 0x05, 0x68], type: 'application/x-protobuf'),
        decoders: [decoder],
      );
      await tester.tap(find.text('Show raw'));
      await tester.pump();
      expect(content('hex'), findsOneWidget);
      expect(find.text('Show decoded'), findsOneWidget);
      expect(find.text('Show raw'), findsNothing);
      await tester.tap(find.text('Show decoded'));
      await tester.pump();
      expect(content('decoded'), findsOneWidget);
      expect(find.text('Show raw'), findsOneWidget);
    });

    testWidgets('showing the raw body of decoded JSON returns to the tree', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        jsonBody('{"a":1}'),
        decoders: [_Decoder('Custom', 'a is 1')],
      );
      expect(chipNames(tester), ['decoded', 'tree', 'pretty', 'raw']);
      await tester.tap(find.text('Show raw'));
      await tester.pump();
      expect(content('tree'), findsOneWidget);
    });

    testWidgets(
      'the first decoder that answers wins and the rest are not asked',
      (tester) async {
        final none = _Decoder('None', null);
        final first = _Decoder('First', 'from the first');
        final second = _Decoder('Second', 'from the second');
        await pumpViewer(
          tester,
          textBody('x', type: 'text/plain'),
          decoders: [none, first, second],
        );
        expect(find.text('Decoded as First'), findsOneWidget);
        expect(find.textContaining('from the first'), findsOneWidget);
        expect(none.calls, 1);
        expect(first.calls, 1);
        expect(second.calls, 0);
      },
    );

    testWidgets('a decoder is asked once, however often the viewer rebuilds', (
      tester,
    ) async {
      final decoder = _Decoder('Once', 'decoded');
      await pumpViewer(
        tester,
        textBody('x', type: 'text/plain'),
        decoders: [decoder],
      );
      await tester.tap(find.byTooltip('Wrap lines'));
      await tester.pump();
      await tester.tap(find.text('Show raw'));
      await tester.pump();
      await tester.tap(find.text('Show decoded'));
      await tester.pump();
      expect(decoder.calls, 1);
    });

    testWidgets('a decoder that throws is ignored', (tester) async {
      final broken = _Decoder('Broken', null, throws: true);
      final good = _Decoder('Good', 'readable');
      await pumpViewer(
        tester,
        textBody('x', type: 'text/plain'),
        decoders: [broken, good],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Decoded as Good'), findsOneWidget);
    });

    testWidgets('when every decoder throws the body is shown as it is', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        textBody('plain words', type: 'text/plain'),
        decoders: [_Decoder('Broken', null, throws: true)],
      );
      expect(tester.takeException(), isNull);
      expect(chipNames(tester), ['raw']);
      expect(find.textContaining('plain words'), findsOneWidget);
    });

    testWidgets('decoded text of a binary body says what is underneath', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        bytesBody([0x0A, 0x05, 0x68, 0x65], type: 'application/x-protobuf'),
        decoders: [_Decoder('Protobuf', 'field 1: he')],
      );
      expect(
        find.text('Binary data, 4 B, application/x-protobuf'),
        findsOneWidget,
      );
      await tester.tap(chip('hex'));
      await tester.pump();
      expect(find.textContaining('Binary data'), findsNothing);
    });

    testWidgets('an empty body is never decoded', (tester) async {
      final decoder = _Decoder('Never', 'x');
      await pumpViewer(tester, FlutwireBody.empty(), decoders: [decoder]);
      expect(decoder.calls, 0);
    });
  });

  group('the look', () {
    for (final tokens in [FlutwireTokens.dark, FlutwireTokens.light]) {
      testWidgets('draws in the ${tokens.brightness.name} look', (
        tester,
      ) async {
        await pumpViewer(
          tester,
          jsonBody('{"name":"Ada","n":[1,2,3]}'),
          tokens: tokens,
        );
        expect(tester.takeException(), isNull);
        for (final mode in ['pretty', 'raw', 'tree']) {
          await tester.tap(chip(mode));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
