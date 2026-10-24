import 'package:flutter/foundation.dart';

import 'model/headers.dart';

/// The header fields the client writes from the request itself. Setting one by
/// hand only fights it: a stale `Content-Length` breaks a body that was edited.
const Set<String> clientManagedHeaders = {
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'keep-alive',
};

/// Whether [value] of the header field [name] is what the redaction policy left
/// in place of a secret, so it cannot be sent.
///
/// A `Cookie` is hidden cookie by cookie, so one that still names its cookies is
/// hidden when any of them is.
bool isHiddenValue(String name, String value, String mask) {
  if (mask.isEmpty) return false;
  if (name.toLowerCase() == 'cookie') {
    return _splitCookies(value, mask).dropped;
  }
  return value == mask;
}

/// A request to send again, as the editor in the inspector built it.
///
/// Flutwire never sends a value it hid: the fields that still hold the mask are
/// left out of [headers] and named in [hidden], so what goes on the wire is
/// exactly what the person read in the editor, minus the mask.
@immutable
final class FlutwireResend {
  const FlutwireResend._({
    required this.from,
    required this.method,
    required this.uri,
    required this.headers,
    required this.hidden,
    required this.body,
  });

  /// Prepares a request that repeats the call with the id [from].
  ///
  /// [headers] are the fields as the editor holds them: blank rows, the fields
  /// the client writes itself and the values that still hold [mask] are not
  /// sent. A null or empty [body] sends no body.
  factory FlutwireResend({
    required int from,
    required String method,
    required Uri uri,
    required Iterable<MapEntry<String, String>> headers,
    required String mask,
    Uint8List? body,
  }) {
    final kept = <MapEntry<String, String>>[];
    final hidden = <String>[];
    void hide(String name) {
      if (!hidden.contains(name)) hidden.add(name);
    }

    for (final field in headers) {
      final name = field.key.trim();
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();
      if (clientManagedHeaders.contains(lower)) continue;
      if (lower == 'cookie' && mask.isNotEmpty) {
        final cookies = _splitCookies(field.value, mask);
        if (cookies.dropped) hide(name);
        if (cookies.live.isNotEmpty) {
          kept.add(MapEntry(name, cookies.live.join('; ')));
        }
        continue;
      }
      if (isHiddenValue(lower, field.value, mask)) {
        hide(name);
        continue;
      }
      kept.add(MapEntry(name, field.value));
    }
    return FlutwireResend._(
      from: from,
      method: method.trim().toUpperCase(),
      uri: uri,
      headers: FlutwireHeaders(kept),
      hidden: List.unmodifiable(hidden),
      body: body == null || body.isEmpty ? null : body,
    );
  }

  /// The id of the call this one repeats.
  final int from;

  /// The method, in upper case.
  final String method;

  /// Where the request goes.
  final Uri uri;

  /// The header fields that go on the wire.
  final FlutwireHeaders headers;

  /// The names of the header fields that were left out because they still hold
  /// the mask.
  final List<String> hidden;

  /// The body, or null for none.
  final Uint8List? body;
}

/// The pieces of a `Cookie` header value, `a=1; b=2`, that do not hold [mask],
/// and whether any piece did.
({List<String> live, bool dropped}) _splitCookies(String header, String mask) {
  final live = <String>[];
  var dropped = false;
  for (final raw in header.split(';')) {
    final piece = raw.trim();
    if (piece.isEmpty) continue;
    final eq = piece.indexOf('=');
    final value = eq < 0 ? piece : piece.substring(eq + 1).trim();
    if (value == mask) {
      dropped = true;
    } else {
      live.add(piece);
    }
  }
  return (live: live, dropped: dropped);
}
