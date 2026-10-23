import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/model/body.dart';
import 'package:flutwire/src/ui/body/body_modes.dart';

import 'helpers.dart';

BodyModes modes(FlutwireBody body, {bool decoded = false}) =>
    BodyModes(body, hasDecoded: decoded);

void main() {
  group('what each kind of body offers', () {
    test('a JSON document: tree, indented, raw', () {
      final m = modes(jsonBody('{"a":1}'));

      expect(m.all, [BodyMode.tree, BodyMode.pretty, BodyMode.raw]);
      expect(m.initial, BodyMode.tree);
    });

    test('XML: indented, raw', () {
      final m = modes(textBody('<a><b/></a>', type: 'application/xml'));

      expect(m.all, [BodyMode.pretty, BodyMode.raw]);
      expect(m.initial, BodyMode.pretty);
    });

    test('HTML and plain text: raw', () {
      expect(modes(textBody('<html></html>', type: 'text/html')).all, [
        BodyMode.raw,
      ]);
      expect(modes(textBody('hello', type: 'text/plain')).all, [BodyMode.raw]);
    });

    test('a form: fields, raw', () {
      final m = modes(
        textBody('a=1&b=2', type: 'application/x-www-form-urlencoded'),
      );

      expect(m.all, [BodyMode.fields, BodyMode.raw]);
      expect(m.initial, BodyMode.fields);
    });

    test('a multipart upload: parts, hex', () {
      final m = modes(multipartBody(['--b', '', '--b--']));

      expect(m.all, [BodyMode.parts, BodyMode.hex]);
    });

    test('an image: preview, hex', () {
      final m = modes(bytesBody(onePixelPng, type: 'image/png'));

      expect(m.all, [BodyMode.preview, BodyMode.hex]);
      expect(m.initial, BodyMode.preview);
    });

    test('anything else: hex', () {
      final m = modes(bytesBody([0x1F, 0x8B, 8, 0]));

      expect(m.all, [BodyMode.hex]);
      expect(m.initial, BodyMode.hex);
    });

    test('nothing: no modes, and raw as the fallback', () {
      final m = modes(FlutwireBody.empty());

      expect(m.all, isEmpty);
      expect(m.initial, BodyMode.raw);
    });
  });

  group('a JSON body that is cut or malformed', () {
    final cut = jsonBody('{"a":1,', total: 2048);

    test('has no tree and no indented form, and opens raw', () {
      final m = modes(cut);

      expect(m.isEnabled(BodyMode.tree), isFalse);
      expect(m.isEnabled(BodyMode.pretty), isFalse);
      expect(m.isEnabled(BodyMode.raw), isTrue);
      expect(m.initial, BodyMode.raw);
    });

    test('still lists the modes, so the toolbar can show them off', () {
      expect(modes(cut).all, [BodyMode.tree, BodyMode.pretty, BodyMode.raw]);
    });
  });

  group('a decoder that recognised the body', () {
    test('puts its mode first and opens on it', () {
      final m = modes(jsonBody('{"a":1}'), decoded: true);

      expect(m.all.first, BodyMode.decoded);
      expect(m.all, hasLength(4));
      expect(m.initial, BodyMode.decoded);
    });

    test('leaves the mode that shows the body itself one call away', () {
      final m = modes(jsonBody('{"a":1}'), decoded: true);

      expect(m.undecoded, BodyMode.tree);
    });

    test('can decode a body that is otherwise only bytes', () {
      final m = modes(bytesBody([0x1F, 0x8B, 8, 0]), decoded: true);

      expect(m.all, [BodyMode.decoded, BodyMode.hex]);
      expect(m.undecoded, BodyMode.hex);
    });
  });

  group('the traits of a mode', () {
    test('only text modes can be searched', () {
      expect(BodyMode.hex.isSearchable, isFalse);
      expect(BodyMode.preview.isSearchable, isFalse);
      for (final mode in [
        BodyMode.decoded,
        BodyMode.tree,
        BodyMode.pretty,
        BodyMode.raw,
        BodyMode.fields,
        BodyMode.parts,
      ]) {
        expect(mode.isSearchable, isTrue, reason: '$mode');
      }
    });

    test('code modes are the ones drawn as lines of text', () {
      expect(BodyMode.values.where((mode) => mode.isCode), [
        BodyMode.decoded,
        BodyMode.pretty,
        BodyMode.raw,
      ]);
    });
  });
}
