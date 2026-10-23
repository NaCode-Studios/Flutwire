import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'body.dart';
import 'headers.dart';

/// One part of a `multipart/form-data` body.
@immutable
final class FlutwireMultipartPart {
  /// Creates a part.
  const FlutwireMultipartPart({
    required this.headers,
    required this.bytes,
    this.name,
    this.filename,
  });

  /// The part's own header fields.
  final FlutwireHeaders headers;

  /// The form field name.
  final String? name;

  /// The file name, for a file upload.
  final String? filename;

  /// The part's content, as far as the body was recorded.
  final Uint8List bytes;

  /// Whether this part is a file rather than a plain field.
  bool get isFile => filename != null;

  /// The part's media type, if it declared one.
  String? get contentType => headers.contentType;

  /// The content as text when it looks like text, otherwise null.
  String? get text {
    final probe = FlutwireBody(bytes: bytes, contentType: contentType);
    switch (probe.kind) {
      case FlutwireBodyKind.image:
      case FlutwireBodyKind.binary:
        return null;
      case FlutwireBodyKind.empty:
        return '';
      case FlutwireBodyKind.json:
      case FlutwireBodyKind.xml:
      case FlutwireBodyKind.html:
      case FlutwireBodyKind.text:
      case FlutwireBodyKind.form:
      case FlutwireBodyKind.multipart:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

/// Splits a `multipart/*` body into its parts.
///
/// A body that was cut off yields the parts that arrived, with the last one
/// holding whatever bytes there were. A body with no boundary yields nothing.
List<FlutwireMultipartPart> parseMultipart(FlutwireBody body) {
  final boundary = body.boundary;
  if (boundary == null || !body.loaded || body.bytes.isEmpty) return const [];
  // Latin-1 maps every byte to one code unit, so offsets in the text are
  // offsets in the bytes, whatever the parts contain.
  final raw = latin1.decode(body.bytes);
  final delimiter = '--$boundary';
  final parts = <FlutwireMultipartPart>[];

  var delimiterAt = raw.indexOf(delimiter);
  while (delimiterAt >= 0) {
    final afterDelimiter = delimiterAt + delimiter.length;
    if (raw.startsWith('--', afterDelimiter)) break; // the closing delimiter
    final start = afterDelimiter + _lineBreakLength(raw, afterDelimiter);
    final breakAt = _breakBeforeNextDelimiter(raw, delimiter, start);
    final end = breakAt < 0 ? raw.length : breakAt;
    final part = _parsePart(raw.substring(start, end));
    if (part != null) parts.add(part);
    if (breakAt < 0) break;
    delimiterAt = raw.indexOf(delimiter, breakAt);
  }
  return parts;
}

int _lineBreakLength(String raw, int index) {
  if (raw.startsWith('\r\n', index)) return 2;
  if (raw.startsWith('\n', index)) return 1;
  return 0;
}

/// The index of the line break that precedes the next delimiter, or -1.
int _breakBeforeNextDelimiter(String raw, String delimiter, int from) {
  final crlf = raw.indexOf('\r\n$delimiter', from);
  final lf = raw.indexOf('\n$delimiter', from);
  if (crlf >= 0 && (lf < 0 || crlf <= lf)) return crlf;
  return lf;
}

FlutwireMultipartPart? _parsePart(String section) {
  var split = section.indexOf('\r\n\r\n');
  var gap = 4;
  if (split < 0) {
    split = section.indexOf('\n\n');
    gap = 2;
  }
  final String head;
  final String content;
  if (split < 0) {
    // A part cut off inside its headers: keep what there is of them.
    head = section;
    content = '';
  } else {
    head = section.substring(0, split);
    content = section.substring(split + gap);
  }
  final fields = <MapEntry<String, String>>[];
  for (final line in head.split(RegExp(r'\r?\n'))) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    fields.add(
      MapEntry(
        line.substring(0, colon).trim(),
        line.substring(colon + 1).trim(),
      ),
    );
  }
  final headers = FlutwireHeaders(fields);
  final disposition = headers.first('content-disposition') ?? '';
  return FlutwireMultipartPart(
    headers: headers,
    name: _parameter(disposition, 'name'),
    filename: _parameter(disposition, 'filename'),
    bytes: Uint8List.fromList(latin1.encode(content)),
  );
}

String? _parameter(String header, String name) {
  final quoted = RegExp(
    '(?:^|[;\\s])$name\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"',
    caseSensitive: false,
  ).firstMatch(header);
  if (quoted != null) return quoted.group(1)!.replaceAll(r'\"', '"');
  final bare = RegExp(
    '(?:^|[;\\s])$name\\s*=\\s*([^;\\s]+)',
    caseSensitive: false,
  ).firstMatch(header);
  return bare?.group(1);
}
