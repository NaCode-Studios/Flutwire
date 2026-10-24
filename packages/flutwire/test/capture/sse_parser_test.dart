import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/capture/messages/sse_parser.dart';

/// Feeds [chunks] to a parser and returns what it reported.
List<SseEvent> parse(List<String> chunks, {int maxChars = 250000}) {
  final events = <SseEvent>[];
  final parser = SseParser(events.add, maxChars: maxChars);
  for (final chunk in chunks) {
    parser.add(utf8.encode(chunk));
  }
  parser.close();
  return events;
}

void main() {
  test('reports an event when the empty line after it arrives', () {
    final events = parse(['data: hello\n\n']);

    expect(events.single.data, 'hello');
    expect(events.single.event, isNull);
    expect(events.single.id, isNull);
  });

  test('waits for the empty line', () {
    final events = <SseEvent>[];
    final parser = SseParser(events.add)..add(utf8.encode('data: a\n'));

    expect(events, isEmpty);

    parser.add(utf8.encode('\n'));

    expect(events.single.data, 'a');
  });

  test('joins several data lines with a line feed', () {
    final events = parse(['data: one\ndata: two\ndata: three\n\n']);

    expect(events.single.data, 'one\ntwo\nthree');
    expect(events.single.totalBytes, 'one\ntwo\nthree'.length);
  });

  test('reads the event name and the id', () {
    final events = parse(['event: tick\nid: 7\ndata: {"n":1}\n\n']);

    expect(events.single.event, 'tick');
    expect(events.single.id, '7');
    expect(events.single.data, '{"n":1}');
  });

  test('keeps the id for the events after it, and the name for one only', () {
    final events = parse(['id: 1\nevent: a\ndata: x\n\n', 'data: y\n\n']);

    expect(events.map((e) => e.id), ['1', '1']);
    expect(events.map((e) => e.event), ['a', null]);
  });

  test('ignores comments, retry and fields it does not know', () {
    final events = parse([': keep alive\nretry: 3000\nnote: x\ndata: ok\n\n']);

    expect(events.single.data, 'ok');
  });

  test('drops one leading space from a value and no more', () {
    final events = parse(['data:  two spaces\n\n']);

    expect(events.single.data, ' two spaces');
  });

  test('takes a line with no colon as a field with an empty value', () {
    final events = parse(['data\n\n']);

    expect(events.single.data, '');
  });

  test('says nothing for an empty line with no data before it', () {
    expect(parse(['\n\n: only a comment\n\n']), isEmpty);
  });

  test('ends a line with a line feed, a carriage return or both', () {
    final events = parse(['data: a\r\n\r\ndata: b\r\rdata: c\n\n']);

    expect(events.map((e) => e.data), ['a', 'b', 'c']);
  });

  test(
    'reads a carriage return and its line feed in two chunks as one end',
    () {
      final events = parse(['data: a\r', '\n\r', '\n']);

      expect(events.map((e) => e.data), ['a']);
    },
  );

  test('puts an event together from pieces of any size', () {
    final text = 'event: e\ndata: split here\n\n';
    final events = <SseEvent>[];
    final parser = SseParser(events.add);
    for (final unit in utf8.encode(text)) {
      parser.add([unit]);
    }

    expect(events.single.event, 'e');
    expect(events.single.data, 'split here');
  });

  test('reads a character that is cut between two chunks', () {
    final bytes = utf8.encode('data: caffè ☕\n\n');
    final events = <SseEvent>[];
    SseParser(events.add)
      ..add(bytes.sublist(0, 10))
      ..add(bytes.sublist(10));

    expect(events.single.data, 'caffè ☕');
    expect(events.single.totalBytes, utf8.encode('caffè ☕').length);
  });

  test('ignores a byte order mark at the start of the stream', () {
    final events = parse(['﻿data: a\n\n']);

    expect(events.single.data, 'a');
  });

  test('drops an event the stream ended in the middle of', () {
    expect(parse(['data: never finished\n']), isEmpty);
  });

  test('keeps a cut data and the size of the whole', () {
    final events = parse(['data: ${'x' * 100}\n\n'], maxChars: 10);

    expect(events.single.data, 'x' * 10);
    expect(events.single.totalBytes, 100);
  });

  test('ignores an id with a null character in it', () {
    final events = parse(['id: a\u0000b\ndata: x\n\n']);

    expect(events.single.id, isNull);
  });

  test('reports an event with an empty data field', () {
    final events = parse(['data:\n\n']);

    expect(events.single.data, '');
  });
}
