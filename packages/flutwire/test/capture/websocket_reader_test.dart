import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire/src/capture/messages/websocket_reader_io.dart';

import '../support/websocket_frames.dart';

typedef Got = ({
  FlutwireMessageKind kind,
  Uint8List payload,
  int total,
  bool undecoded,
});

/// What a reader reports for [chunks].
List<Got> read(
  List<List<int>> chunks, {
  bool deflate = false,
  bool noContextTakeover = false,
  int maxBytes = 1 << 20,
  void Function(WebSocketReader reader)? inspect,
}) {
  final got = <Got>[];
  final reader = WebSocketReader(
    onMessage: (kind, payload, total, {required undecoded}) => got.add((
      kind: kind,
      payload: payload,
      total: total,
      undecoded: undecoded,
    )),
    deflate: deflate,
    noContextTakeover: noContextTakeover,
    maxBytes: maxBytes,
  );
  chunks.forEach(reader.add);
  inspect?.call(reader);
  return got;
}

List<int> text(String value) => utf8.encode(value);

/// A message as a sender that compresses writes it: raw deflate, flushed, with
/// the four bytes at the end cut off.
List<int> deflated(RawZLibFilter filter, String message) {
  final data = utf8.encode(message);
  filter.process(data, 0, data.length);
  final out = BytesBuilder();
  while (true) {
    final piece = filter.processed();
    if (piece == null || piece.isEmpty) break;
    out.add(piece);
  }
  final bytes = out.toBytes();
  return bytes.sublist(0, bytes.length - 4);
}

void main() {
  group('a message in one frame', () {
    test('is a text message with its payload', () {
      final got = read([frame(1, text('hello'))]);

      expect(got.single.kind, FlutwireMessageKind.text);
      expect(utf8.decode(got.single.payload), 'hello');
      expect(got.single.total, 5);
      expect(got.single.undecoded, isFalse);
    });

    test('is a binary message when the opcode says so', () {
      final got = read([
        frame(2, [1, 2, 3]),
      ]);

      expect(got.single.kind, FlutwireMessageKind.binary);
      expect(got.single.payload, [1, 2, 3]);
    });

    test('is read through the mask a client puts on it', () {
      final got = read([frame(1, text('masked'), masked: true)]);

      expect(utf8.decode(got.single.payload), 'masked');
    });

    test('may be empty', () {
      final got = read([frame(1, [])]);

      expect(got.single.payload, isEmpty);
      expect(got.single.total, 0);
    });

    test('has a length written in two bytes when it is long', () {
      final payload = List.filled(300, 65);
      final got = read([frame(1, payload)]);

      expect(got.single.payload, hasLength(300));
    });

    test('has a length written in eight bytes when it is longer', () {
      final payload = List.filled(70000, 66);
      final got = read([frame(2, payload, masked: true)]);

      expect(got.single.total, 70000);
      expect(got.single.payload.every((b) => b == 66), isTrue);
    });

    test('arrives however the bytes are cut', () {
      final bytes = frame(1, text('one byte at a time'), masked: true);
      final got = read([
        for (final byte in bytes) [byte],
      ]);

      expect(utf8.decode(got.single.payload), 'one byte at a time');
    });

    test('is followed by the next in the same chunk', () {
      final both = [...frame(1, text('a')), ...frame(1, text('b'))];
      final got = read([both]);

      expect(got.map((g) => utf8.decode(g.payload)), ['a', 'b']);
    });
  });

  test('a message in several frames is joined into one', () {
    final got = read([
      frame(1, text('hel'), fin: false),
      frame(0, text('lo '), fin: false),
      frame(0, text('world')),
    ]);

    expect(got, hasLength(1));
    expect(utf8.decode(got.single.payload), 'hello world');
    expect(got.single.total, 11);
  });

  test('control frames between the pieces of a message are messages too', () {
    final got = read([
      frame(1, text('hel'), fin: false),
      frame(9, text('?')),
      frame(0, text('lo')),
    ]);

    expect(got.map((g) => g.kind), [
      FlutwireMessageKind.ping,
      FlutwireMessageKind.text,
    ]);
    expect(utf8.decode(got.last.payload), 'hello');
  });

  group('control frames', () {
    test('are a ping, a pong and a close', () {
      final got = read([
        frame(9, text('a')),
        frame(10, text('b')),
        frame(8, [0x03, 0xe8, ...text('bye')]),
      ]);

      expect(got.map((g) => g.kind), [
        FlutwireMessageKind.ping,
        FlutwireMessageKind.pong,
        FlutwireMessageKind.close,
      ]);
      final close = FlutwireMessage(
        index: 0,
        sent: false,
        at: DateTime.utc(2026),
        kind: FlutwireMessageKind.close,
        bytes: got.last.payload,
        totalBytes: got.last.total,
      );
      expect(close.closeCode, 1000);
      expect(close.closeReason, 'bye');
    });

    test('may have no payload at all', () {
      final got = read([frame(8, [])]);

      expect(got.single.kind, FlutwireMessageKind.close);
      expect(got.single.payload, isEmpty);
    });
  });

  test('keeps the first bytes of a long payload and counts all of it', () {
    final got = read([frame(1, List.filled(5000, 120))], maxBytes: 100);

    expect(got.single.payload, hasLength(100));
    expect(got.single.total, 5000);
  });

  group('compression', () {
    test('a compressed message is decompressed', () {
      final filter = RawZLibFilter.deflateFilter(raw: true);
      final got = read([
        frame(1, deflated(filter, '{"hello":"world"}'), rsv1: true),
      ], deflate: true);

      expect(utf8.decode(got.single.payload), '{"hello":"world"}');
      expect(got.single.total, 17);
      expect(got.single.undecoded, isFalse);
    });

    test('messages that share a window are read in order', () {
      final filter = RawZLibFilter.deflateFilter(raw: true);
      final first = deflated(filter, 'the same words, the same words');
      final second = deflated(filter, 'the same words, the same words');
      // The second one points back into the first, so it only reads right if
      // the window was kept.
      expect(second.length, lessThan(first.length));

      final got = read([
        frame(1, first, rsv1: true),
        frame(1, second, rsv1: true),
      ], deflate: true);

      expect(got.map((g) => utf8.decode(g.payload)), [
        'the same words, the same words',
        'the same words, the same words',
      ]);
    });

    test('messages that stand alone are each read from a fresh window', () {
      final got = read(
        [
          frame(
            1,
            deflated(RawZLibFilter.deflateFilter(raw: true), 'one'),
            rsv1: true,
          ),
          frame(
            1,
            deflated(RawZLibFilter.deflateFilter(raw: true), 'two'),
            rsv1: true,
          ),
        ],
        deflate: true,
        noContextTakeover: true,
      );

      expect(got.map((g) => utf8.decode(g.payload)), ['one', 'two']);
    });

    test('a compressed message in two frames is read as one', () {
      final bytes = deflated(
        RawZLibFilter.deflateFilter(raw: true),
        'in two parts',
      );
      final half = bytes.length ~/ 2;
      final got = read([
        frame(1, bytes.sublist(0, half), fin: false, rsv1: true),
        frame(0, bytes.sublist(half)),
      ], deflate: true);

      expect(utf8.decode(got.single.payload), 'in two parts');
    });

    test('a plain message is untouched while compression is on', () {
      final got = read([frame(1, text('plain'))], deflate: true);

      expect(utf8.decode(got.single.payload), 'plain');
    });

    test('bytes that are not compressed are reported as not decoded', () {
      final got = read([
        frame(1, [1, 2, 3, 4, 5, 6, 7, 8], rsv1: true),
        frame(1, [9, 9, 9], rsv1: true),
      ], deflate: true);

      expect(got.map((g) => g.undecoded), [isTrue, isTrue]);
      expect(got.last.payload, [9, 9, 9]);
    });

    test('is not expected unless the handshake agreed to it', () {
      WebSocketReader? seen;
      final got = read([
        frame(1, text('hi'), rsv1: true),
      ], inspect: (reader) => seen = reader);

      expect(got, isEmpty);
      expect(seen!.broken, isTrue);
    });
  });

  group('what cannot be read', () {
    bool brokenBy(List<int> bytes, {bool deflate = false}) {
      late WebSocketReader reader;
      read([bytes], deflate: deflate, inspect: (r) => reader = r);
      return reader.broken;
    }

    test('a reserved bit stops the reader', () {
      expect(brokenBy([0xA1, 0x00]), isTrue);
    });

    test('an opcode that does not exist stops the reader', () {
      expect(brokenBy(frame(3, [1])), isTrue);
      expect(brokenBy(frame(11, [])), isTrue);
    });

    test('a continuation with nothing to continue stops the reader', () {
      expect(brokenBy(frame(0, [1])), isTrue);
    });

    test('a new message in the middle of one stops the reader', () {
      final broken = [
        ...frame(1, text('a'), fin: false),
        ...frame(1, text('b')),
      ];

      expect(brokenBy(broken), isTrue);
    });

    test('a control frame in pieces stops the reader', () {
      expect(brokenBy(frame(9, text('x'), fin: false)), isTrue);
    });

    test('a control frame that is too long stops the reader', () {
      expect(brokenBy(frame(9, List.filled(126, 0))), isTrue);
    });

    test('a length that cannot be real stops the reader', () {
      expect(
        brokenBy([0x82, 127, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        isTrue,
      );
    });

    test('says nothing more once it has stopped', () {
      final got = read([
        frame(3, [1]),
        frame(1, text('after')),
      ]);

      expect(got, isEmpty);
    });
  });
}
