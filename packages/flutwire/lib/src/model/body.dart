import 'dart:convert';
import 'package:flutter/foundation.dart';

/// What a recorded body looks like, which decides how the inspector shows it.
enum FlutwireBodyKind {
  /// Nothing was sent.
  empty,

  /// JSON, by media type or by content.
  json,

  /// XML, including SVG and other `+xml` types.
  xml,

  /// An HTML document.
  html,

  /// Any other text.
  text,

  /// `application/x-www-form-urlencoded`.
  form,

  /// `multipart/*`, such as a file upload.
  multipart,

  /// A raster or vector image the inspector can draw.
  image,

  /// Bytes that are not text.
  binary,
}

/// The body of a request or a response, as far as it was recorded.
///
/// Only the first `maxBodyBytes` are kept. [totalBytes] is the size the app
/// actually sent or received, so the inspector can say "250 KB of 3.2 MB" and
/// never mistake a cut body for a complete one.
@immutable
final class FlutwireBody {
  /// Creates a body from the bytes that were kept.
  ///
  /// [totalBytes] defaults to the length of [bytes], meaning nothing was cut.
  FlutwireBody({required this.bytes, int? totalBytes, this.contentType})
    : totalBytes = totalBytes ?? bytes.length,
      loaded = true,
      _keptBytes = bytes.length;

  /// A body whose bytes live on disk and have not been read yet. It keeps the
  /// size and the media type so a list row can still describe it.
  FlutwireBody.unloaded({
    required this.totalBytes,
    this.contentType,
    int keptBytes = 0,
  }) : bytes = _none,
       loaded = false,
       _keptBytes = keptBytes;

  /// Restores the description written by [toJson], without the bytes.
  factory FlutwireBody.fromJson(Map<String, Object?> json) =>
      FlutwireBody.unloaded(
        totalBytes: (json['total'] as num?)?.toInt() ?? 0,
        contentType: json['type'] as String?,
        keptBytes: (json['kept'] as num?)?.toInt() ?? 0,
      );

  /// A body that was never sent.
  factory FlutwireBody.empty() => FlutwireBody(bytes: _none);

  static final Uint8List _none = Uint8List(0);

  /// The bytes that were kept, at most the configured limit.
  final Uint8List bytes;

  /// The size of the whole body in bytes, including what was not kept.
  final int totalBytes;

  /// The `Content-Type` header value, parameters included.
  final String? contentType;

  /// Whether [bytes] holds the recorded bytes. A summary read from disk does
  /// not, until the full call is loaded.
  final bool loaded;

  final int _keptBytes;

  /// How many bytes were kept, whether or not they are loaded now.
  int get keptBytes => _keptBytes;

  /// Whether nothing was sent.
  bool get isEmpty => totalBytes == 0;

  /// Whether some of the body was not kept.
  bool get truncated => loaded && totalBytes > bytes.length;

  /// The media type without parameters, lower-cased, or null.
  String? get mimeType {
    final raw = contentType;
    if (raw == null) return null;
    final end = raw.indexOf(';');
    final mime = (end < 0 ? raw : raw.substring(0, end)).trim().toLowerCase();
    return mime.isEmpty ? null : mime;
  }

  /// The `charset` parameter of the media type, lower-cased, or null.
  String? get charset {
    final raw = contentType;
    if (raw == null) return null;
    final match = RegExp(
      r'charset\s*=\s*"?([^";\s]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    return match?.group(1)?.toLowerCase();
  }

  /// The multipart boundary parameter, or null.
  String? get boundary {
    final raw = contentType;
    if (raw == null) return null;
    final match = RegExp(
      r'boundary\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(raw);
    return match?.group(1);
  }

  /// How this body should be shown.
  late final FlutwireBodyKind kind = _detectKind();

  /// The body decoded as text, or null when it is not text or not loaded.
  late final String? text = _decode();

  late final ({bool valid, Object? value}) _json = _parseJson();

  /// The parsed JSON value, or null if the body is not complete, valid JSON.
  Object? get jsonValue => _json.value;

  /// Whether [jsonValue] holds a parsed document, which a bare `null` also is.
  bool get isValidJson => _json.valid;

  /// The decoded fields of a form body, in order, or an empty list.
  late final List<MapEntry<String, String>> formFields = _parseForm();

  /// The text re-indented for reading: JSON and XML are pretty-printed, any
  /// other text is returned as it came.
  late final String? prettyText = _pretty();

  FlutwireBodyKind _detectKind() {
    if (totalBytes == 0) return FlutwireBodyKind.empty;
    final mime = mimeType;
    if (mime != null) {
      if (mime == 'image/svg+xml') return FlutwireBodyKind.xml;
      if (mime.startsWith('image/')) return FlutwireBodyKind.image;
      if (mime == 'application/json' ||
          mime == 'text/json' ||
          mime.endsWith('+json')) {
        return FlutwireBodyKind.json;
      }
      if (mime == 'application/xml' ||
          mime == 'text/xml' ||
          mime.endsWith('+xml')) {
        return FlutwireBodyKind.xml;
      }
      if (mime == 'text/html') return FlutwireBodyKind.html;
      if (mime == 'application/x-www-form-urlencoded') {
        return FlutwireBodyKind.form;
      }
      if (mime.startsWith('multipart/')) return FlutwireBodyKind.multipart;
      if (mime.startsWith('text/')) return FlutwireBodyKind.text;
    }
    return _sniff();
  }

  FlutwireBodyKind _sniff() {
    if (!loaded || bytes.isEmpty) return FlutwireBodyKind.binary;
    if (_looksLikeImage(bytes)) return FlutwireBodyKind.image;
    if (_hasBinaryMagic(bytes)) return FlutwireBodyKind.binary;
    final head = _tryUtf8(bytes);
    if (head == null) return FlutwireBodyKind.binary;
    final trimmed = head.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return FlutwireBodyKind.json;
    }
    if (trimmed.startsWith('<?xml')) return FlutwireBodyKind.xml;
    final lower = trimmed.length > 64
        ? trimmed.substring(0, 64).toLowerCase()
        : trimmed.toLowerCase();
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
      return FlutwireBodyKind.html;
    }
    if (trimmed.startsWith('<')) return FlutwireBodyKind.xml;
    return FlutwireBodyKind.text;
  }

  String? _decode() {
    if (!loaded) return null;
    switch (kind) {
      case FlutwireBodyKind.empty:
        return '';
      case FlutwireBodyKind.image:
      case FlutwireBodyKind.binary:
      case FlutwireBodyKind.multipart:
        return null;
      case FlutwireBodyKind.json:
      case FlutwireBodyKind.xml:
      case FlutwireBodyKind.html:
      case FlutwireBodyKind.text:
      case FlutwireBodyKind.form:
        final cs = charset;
        if (cs == 'iso-8859-1' || cs == 'latin1' || cs == 'us-ascii') {
          return latin1.decode(bytes, allowInvalid: true);
        }
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  ({bool valid, Object? value}) _parseJson() {
    const invalid = (valid: false, value: null);
    if (kind != FlutwireBodyKind.json || truncated) return invalid;
    final source = text;
    if (source == null || source.trim().isEmpty) return invalid;
    try {
      return (valid: true, value: jsonDecode(source));
    } on FormatException {
      return invalid;
    }
  }

  List<MapEntry<String, String>> _parseForm() {
    if (kind != FlutwireBodyKind.form) return const [];
    final source = text;
    if (source == null || source.isEmpty) return const [];
    return parseFormEncoded(source);
  }

  String? _pretty() {
    final source = text;
    if (source == null) return null;
    if (kind == FlutwireBodyKind.json) {
      if (isValidJson) {
        return const JsonEncoder.withIndent('  ').convert(jsonValue);
      }
      return source;
    }
    if (kind == FlutwireBodyKind.xml) return prettyXml(source);
    return source;
  }

  /// A description without the bytes, for the summary kept on disk.
  Map<String, Object?> toJson() => {
    'total': totalBytes,
    'kept': keptBytes,
    'type': contentType,
  };

  /// A copy that carries [bytes] in place of the placeholder.
  FlutwireBody withBytes(Uint8List bytes) => FlutwireBody(
    bytes: bytes,
    totalBytes: totalBytes,
    contentType: contentType,
  );

  /// A copy that keeps the description and lets go of the bytes.
  FlutwireBody unload() => FlutwireBody.unloaded(
    totalBytes: totalBytes,
    contentType: contentType,
    keptBytes: keptBytes,
  );

  @override
  String toString() =>
      'FlutwireBody($mimeType, ${bytes.length} of $totalBytes bytes)';
}

/// Splits `a=1&b=2` into decoded pairs, keeping order and repeats.
List<MapEntry<String, String>> parseFormEncoded(String source) {
  final out = <MapEntry<String, String>>[];
  for (final part in source.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    final rawKey = eq < 0 ? part : part.substring(0, eq);
    final rawValue = eq < 0 ? '' : part.substring(eq + 1);
    out.add(MapEntry(_decodeComponent(rawKey), _decodeComponent(rawValue)));
  }
  return out;
}

String _decodeComponent(String raw) {
  final spaced = raw.replaceAll('+', ' ');
  try {
    return Uri.decodeComponent(spaced);
  } on ArgumentError {
    return spaced;
  }
}

/// Re-indents XML for reading. It works on the text and does not validate it,
/// so a document that is cut short or not well formed still comes back.
String prettyXml(String source) {
  final tokens = RegExp(r'<[^>]+>|[^<]+').allMatches(source);
  final out = StringBuffer();
  var depth = 0;
  var afterText = false;
  for (final m in tokens) {
    final token = m.group(0)!;
    final isTag = token.startsWith('<');
    if (!isTag) {
      final text = token.trim();
      if (text.isEmpty) continue;
      out.write(text);
      afterText = true;
      continue;
    }
    final closing = token.startsWith('</');
    final selfClosing =
        token.endsWith('/>') ||
        token.startsWith('<?') ||
        token.startsWith('<!');
    if (closing) depth = depth > 0 ? depth - 1 : 0;
    if (!(closing && afterText)) {
      if (out.isNotEmpty) out.write('\n');
      out.write('  ' * depth);
    }
    out.write(token);
    afterText = false;
    if (!closing && !selfClosing) depth++;
  }
  return out.toString();
}

String? _tryUtf8(Uint8List bytes) {
  // Judge a prefix. A window that ends inside a multi-byte character yields at
  // most one replacement character, which the threshold below absorbs.
  final end = bytes.length > 4096 ? 4096 : bytes.length;
  final text = utf8.decode(
    Uint8List.sublistView(bytes, 0, end),
    allowMalformed: true,
  );
  var bad = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0xFFFD ||
        (unit < 32 && unit != 9 && unit != 10 && unit != 13)) {
      bad++;
    }
  }
  return bad * 50 > text.length ? null : text;
}

bool _startsWith(Uint8List b, List<int> magic, [int offset = 0]) {
  if (b.length < offset + magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (b[offset + i] != magic[i]) return false;
  }
  return true;
}

bool _looksLikeImage(Uint8List b) =>
    _startsWith(b, [0x89, 0x50, 0x4E, 0x47]) || // PNG
    _startsWith(b, [0xFF, 0xD8, 0xFF]) || // JPEG
    _startsWith(b, [0x47, 0x49, 0x46, 0x38]) || // GIF
    _startsWith(b, [0x42, 0x4D]) || // BMP
    (_startsWith(b, [0x52, 0x49, 0x46, 0x46]) &&
        _startsWith(b, [0x57, 0x45, 0x42, 0x50], 8)); // WebP

bool _hasBinaryMagic(Uint8List b) =>
    _startsWith(b, [0x25, 0x50, 0x44, 0x46]) || // PDF
    _startsWith(b, [0x1F, 0x8B]) || // gzip
    _startsWith(b, [0x50, 0x4B, 0x03, 0x04]) || // zip
    _startsWith(b, [0x28, 0xB5, 0x2F, 0xFD]); // zstd
