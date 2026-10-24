import 'dart:convert';
import 'dart:typed_data';

/// Binary content in a value a decoder read. It is written as hex, the way the
/// inspector writes bytes everywhere else.
final class DecodedBytes {
  /// Wraps [bytes].
  const DecodedBytes(this.bytes);

  /// The bytes.
  final Uint8List bytes;

  /// How many bytes are written out before the text says there are more.
  static const int shown = 64;

  @override
  String toString() {
    final head = bytes.length <= shown ? bytes : bytes.sublist(0, shown);
    final hex = [
      for (final byte in head) byte.toRadixString(16).padLeft(2, '0'),
    ].join(' ');
    return bytes.length > shown ? '$hex … (${bytes.length} bytes)' : hex;
  }
}

/// Writes a value a decoder read as indented text that reads like JSON.
///
/// It takes `null`, `bool`, `int`, `BigInt`, `double`, `String`, `DateTime`,
/// [DecodedBytes], lists, and maps with string keys, and keeps the order of a
/// map. It is not JSON where JSON cannot say it: a number too big for a double
/// is written out in full, `NaN` and the infinities are strings, and bytes are
/// a string of hex.
String renderDecoded(Object? value) {
  final out = StringBuffer();
  _write(out, value, 0);
  return out.toString();
}

/// How deep a value is followed before the text gives up and writes `…`.
const int _maxDepth = 64;

/// How long a list of plain values may be and still go on one line.
const int _inlineWidth = 72;

void _write(StringBuffer out, Object? value, int depth) {
  if (depth > _maxDepth) {
    out.write('"…"');
    return;
  }
  switch (value) {
    case null:
      out.write('null');
    case final bool flag:
      out.write(flag);
    case final int number:
      out.write(number);
    case final BigInt number:
      out.write(number);
    case final double number:
      out.write(number.isFinite ? number : jsonEncode(number.toString()));
    case final String text:
      out.write(jsonEncode(text));
    case final DateTime time:
      out.write(jsonEncode(time.toUtc().toIso8601String()));
    case final DecodedBytes bytes:
      out.write(jsonEncode(bytes.toString()));
    case final List<Object?> list:
      _writeList(out, list, depth);
    case final Map<String, Object?> map:
      _writeMap(out, map, depth);
    default:
      out.write(jsonEncode('$value'));
  }
}

bool _isPlain(Object? value) => value is! List<Object?> && value is! Map;

void _writeList(StringBuffer out, List<Object?> list, int depth) {
  if (list.isEmpty) {
    out.write('[]');
    return;
  }
  if (list.every(_isPlain)) {
    final line = StringBuffer('[');
    for (var i = 0; i < list.length; i++) {
      if (i > 0) line.write(', ');
      _write(line, list[i], depth + 1);
    }
    line.write(']');
    if (line.length <= _inlineWidth) {
      out.write(line);
      return;
    }
  }
  final inner = '  ' * (depth + 1);
  out.writeln('[');
  for (var i = 0; i < list.length; i++) {
    out.write(inner);
    _write(out, list[i], depth + 1);
    out.writeln(i == list.length - 1 ? '' : ',');
  }
  out.write('${'  ' * depth}]');
}

void _writeMap(StringBuffer out, Map<String, Object?> map, int depth) {
  if (map.isEmpty) {
    out.write('{}');
    return;
  }
  final inner = '  ' * (depth + 1);
  out.writeln('{');
  var left = map.length;
  for (final entry in map.entries) {
    out.write('$inner${jsonEncode(entry.key)}: ');
    _write(out, entry.value, depth + 1);
    out.writeln(--left == 0 ? '' : ',');
  }
  out.write('${'  ' * depth}}');
}
