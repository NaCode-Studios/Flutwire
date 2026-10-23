import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../model/body.dart';
import '../model/cookies.dart';
import '../model/headers.dart';

/// What to hide from a call before it is stored, shown or shared.
///
/// Redaction runs when a call is recorded, so a secret never reaches memory,
/// the disk, a notification or an export. Names are matched without regard to
/// case.
@immutable
final class FlutwireRedaction {
  /// Creates a redaction policy. Without arguments it hides the headers that
  /// carry credentials and nothing else.
  const FlutwireRedaction({
    this.headers = defaultHeaders,
    this.queryParameters = const {},
    this.bodyFields = const {},
    this.mask = '[redacted]',
  });

  /// Hide nothing.
  static const FlutwireRedaction none = FlutwireRedaction(headers: {});

  /// The header fields that carry credentials.
  static const Set<String> defaultHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
  };

  /// Header fields whose values are replaced by [mask]. For `cookie` and
  /// `set-cookie` only the cookie values are replaced and the names and
  /// attributes stay.
  final Set<String> headers;

  /// Query parameters whose values are replaced by [mask] in the URL.
  final Set<String> queryParameters;

  /// Field names whose values are replaced by [mask] in JSON, form and
  /// `key=value` text bodies, at any depth.
  final Set<String> bodyFields;

  /// The text that takes the place of a hidden value.
  final String mask;

  /// A copy of [source] with the configured headers hidden.
  ///
  /// A hidden header is replaced by [mask], except `Cookie` and `Set-Cookie`:
  /// there only the values of the cookies are replaced, so the inspector can
  /// still list their names and attributes.
  FlutwireHeaders applyToHeaders(FlutwireHeaders source) {
    if (headers.isEmpty || source.isEmpty) return source;
    final hidden = {for (final name in headers) name.toLowerCase()};
    return FlutwireHeaders([
      for (final field in source.entries)
        MapEntry(
          field.key,
          hidden.contains(field.key.toLowerCase())
              ? _hide(field.key.toLowerCase(), field.value)
              : field.value,
        ),
    ]);
  }

  String _hide(String name, String value) => switch (name) {
    'cookie' => maskCookieHeader(value, mask),
    'set-cookie' => maskSetCookie(value, mask),
    _ => mask,
  };

  /// A copy of [uri] with the configured query values hidden.
  Uri applyToUri(Uri uri) {
    if (queryParameters.isEmpty || !uri.hasQuery) return uri;
    final lower = {for (final n in queryParameters) n.toLowerCase()};
    final pairs = parseFormEncoded(uri.query);
    if (!pairs.any((p) => lower.contains(p.key.toLowerCase()))) return uri;
    final query = pairs
        .map((p) {
          final key = Uri.encodeQueryComponent(p.key);
          final value = lower.contains(p.key.toLowerCase())
              ? Uri.encodeQueryComponent(mask)
              : Uri.encodeQueryComponent(p.value);
          return '$key=$value';
        })
        .join('&');
    return uri.replace(query: query);
  }

  /// A copy of [bytes] with the configured fields hidden, or [bytes] itself
  /// when nothing needed hiding.
  ///
  /// The masking works on the text, so it also covers a body that was cut off
  /// before it became valid JSON.
  Uint8List applyToBody(Uint8List bytes, {required String? contentType}) {
    if (bodyFields.isEmpty || bytes.isEmpty) return bytes;
    final probe = FlutwireBody(bytes: bytes, contentType: contentType);
    final kind = probe.kind;
    if (kind != FlutwireBodyKind.json &&
        kind != FlutwireBodyKind.form &&
        kind != FlutwireBodyKind.text) {
      return bytes;
    }
    final text = probe.text;
    if (text == null) return bytes;
    final masked = kind == FlutwireBodyKind.form
        ? _maskForm(text)
        : _maskJsonLike(text);
    return identical(masked, text)
        ? bytes
        : Uint8List.fromList(utf8.encode(masked));
  }

  String _maskForm(String text) {
    final lower = {for (final n in bodyFields) n.toLowerCase()};
    var changed = false;
    final parts = text.split('&').map((part) {
      final eq = part.indexOf('=');
      if (eq < 0) return part;
      final key = _safeDecode(part.substring(0, eq)).toLowerCase();
      if (!lower.contains(key)) return part;
      changed = true;
      return '${part.substring(0, eq)}=${Uri.encodeQueryComponent(mask)}';
    }).toList();
    return changed ? parts.join('&') : text;
  }

  String _maskJsonLike(String text) {
    var out = text;
    for (final name in bodyFields) {
      final key = RegExp.escape(name);
      // "name": "value" | number | true | false | null
      final json = RegExp(
        '("$key"\\s*:\\s*)("(?:[^"\\\\]|\\\\.)*"|-?[0-9][0-9.eE+-]*|true|false|null)',
        caseSensitive: false,
      );
      out = out.replaceAllMapped(
        json,
        (m) => '${m.group(1)}${jsonEncode(mask)}',
      );
      // name=value in plain text
      final plain = RegExp(
        '(\\b$key\\s*=\\s*)([^\\s&,;]+)',
        caseSensitive: false,
      );
      out = out.replaceAllMapped(plain, (m) => '${m.group(1)}$mask');
    }
    return out == text ? text : out;
  }

  static String _safeDecode(String raw) {
    try {
      return Uri.decodeQueryComponent(raw);
    } on ArgumentError {
      return raw;
    }
  }
}
