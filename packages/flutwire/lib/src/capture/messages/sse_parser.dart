import 'dart:convert';

/// A server-sent event, as the stream wrote it.
final class SseEvent {
  /// Creates an event.
  const SseEvent({
    required this.data,
    required this.totalBytes,
    this.event,
    this.id,
  });

  /// The `data:` lines joined by a line feed, cut at the limit the parser was
  /// given.
  final String data;

  /// The size of the whole of [data] in UTF-8 bytes.
  final int totalBytes;

  /// The `event:` field, when the event had one.
  final String? event;

  /// The last `id:` the stream sent, which stays in force for the events after
  /// it.
  final String? id;
}

/// Reads a `text/event-stream` as it arrives and reports each event once it is
/// complete.
///
/// It follows the rules of the HTML standard: lines end with a line feed, a
/// carriage return or both, a line that starts with a colon is a comment, an
/// event ends at an empty line, and a leading byte order mark is ignored.
final class SseParser {
  /// Creates a parser that calls [onEvent] for each event. A `data` field
  /// longer than [maxChars] is cut there, and its real size is reported.
  SseParser(this._onEvent, {this.maxChars = 250000}) {
    _decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(_TextSink(_text));
  }

  final void Function(SseEvent event) _onEvent;

  /// How many characters of an event's data are kept.
  final int maxChars;

  late final Sink<List<int>> _decoder;
  final StringBuffer _line = StringBuffer();
  final StringBuffer _data = StringBuffer();
  bool _first = true;
  bool _afterCarriageReturn = false;
  bool _hasData = false;
  int _dataBytes = 0;
  int _kept = 0;
  String? _eventType;
  String? _lastId;

  /// Feeds the next [chunk] of the stream.
  void add(List<int> chunk) => _decoder.add(chunk);

  /// Says the stream ended. An event that was not completed by an empty line
  /// is dropped, as the standard asks.
  void close() => _decoder.close();

  void _text(String chunk) {
    var text = chunk;
    if (_first) {
      _first = false;
      if (text.startsWith('﻿')) text = text.substring(1);
    }
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (_afterCarriageReturn) {
        _afterCarriageReturn = false;
        if (unit == 0x0A) continue;
      }
      if (unit == 0x0D) {
        _endOfLine();
        _afterCarriageReturn = true;
      } else if (unit == 0x0A) {
        _endOfLine();
      } else {
        _line.writeCharCode(unit);
      }
    }
  }

  void _endOfLine() {
    final line = _line.toString();
    _line.clear();
    if (line.isEmpty) {
      _dispatch();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final name = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (name) {
      case 'event':
        _eventType = value;
      case 'data':
        _addData(value);
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
    }
  }

  void _addData(String value) {
    if (_hasData) {
      _dataBytes += 1;
      _write('\n');
    }
    _hasData = true;
    _dataBytes += _utf8Length(value);
    _write(value);
  }

  void _write(String text) {
    final room = maxChars - _kept;
    if (room <= 0) return;
    final piece = text.length <= room ? text : text.substring(0, room);
    _data.write(piece);
    _kept += piece.length;
  }

  void _dispatch() {
    final had = _hasData;
    final type = _eventType;
    final data = _data.toString();
    final bytes = _dataBytes;
    _data.clear();
    _hasData = false;
    _dataBytes = 0;
    _kept = 0;
    _eventType = null;
    if (!had) return;
    _onEvent(
      SseEvent(
        data: data,
        totalBytes: bytes,
        event: type == null || type.isEmpty ? null : type,
        id: _lastId == null || _lastId!.isEmpty ? null : _lastId,
      ),
    );
  }

  static int _utf8Length(String text) {
    var bytes = 0;
    for (final unit in text.codeUnits) {
      if (unit < 0x80) {
        bytes += 1;
      } else if (unit < 0x800) {
        bytes += 2;
      } else if (unit >= 0xD800 && unit <= 0xDFFF) {
        // Half of a surrogate pair, which is four bytes in all.
        bytes += 2;
      } else {
        bytes += 3;
      }
    }
    return bytes;
  }
}

class _TextSink implements Sink<String> {
  _TextSink(this._onText);

  final void Function(String text) _onText;

  @override
  void add(String data) => _onText(data);

  @override
  void close() {}
}
