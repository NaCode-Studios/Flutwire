import 'package:flutter/foundation.dart';

/// A cookie, as sent in a `Cookie` header or set by a `Set-Cookie` header.
@immutable
final class FlutwireCookie {
  /// Creates a cookie.
  const FlutwireCookie({
    required this.name,
    required this.value,
    this.path,
    this.domain,
    this.expires,
    this.maxAge,
    this.sameSite,
    this.httpOnly = false,
    this.secure = false,
  });

  /// The cookie name.
  final String name;

  /// The cookie value.
  final String value;

  /// The `Path` attribute.
  final String? path;

  /// The `Domain` attribute.
  final String? domain;

  /// The `Expires` attribute, as the server wrote it.
  final String? expires;

  /// The `Max-Age` attribute, in seconds.
  final String? maxAge;

  /// The `SameSite` attribute.
  final String? sameSite;

  /// Whether the cookie is `HttpOnly`.
  final bool httpOnly;

  /// Whether the cookie is `Secure`.
  final bool secure;

  /// The attributes that are set, as short labels for display.
  List<String> get attributes => [
    if (path != null) 'Path=$path',
    if (domain != null) 'Domain=$domain',
    if (expires != null) 'Expires=$expires',
    if (maxAge != null) 'Max-Age=$maxAge',
    if (sameSite != null) 'SameSite=$sameSite',
    if (httpOnly) 'HttpOnly',
    if (secure) 'Secure',
  ];
}

/// The cookies in the value of a `Cookie` request header: `a=1; b=2`.
List<FlutwireCookie> parseCookieHeader(String header) => [
  for (final pair in header.split(';'))
    if (pair.contains('='))
      FlutwireCookie(
        name: pair.substring(0, pair.indexOf('=')).trim(),
        value: pair.substring(pair.indexOf('=') + 1).trim(),
      ),
];

/// The cookie in the value of a `Set-Cookie` response header, or null if it
/// has no name.
FlutwireCookie? parseSetCookie(String header) {
  final segments = header.split(';').map((s) => s.trim()).toList();
  final first = segments.first;
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  String? path, domain, expires, maxAge, sameSite;
  var httpOnly = false;
  var secure = false;
  for (final attribute in segments.skip(1)) {
    final at = attribute.indexOf('=');
    final key = (at < 0 ? attribute : attribute.substring(0, at)).toLowerCase();
    final value = at < 0 ? '' : attribute.substring(at + 1);
    switch (key) {
      case 'path':
        path = value;
      case 'domain':
        domain = value;
      case 'expires':
        expires = value;
      case 'max-age':
        maxAge = value;
      case 'samesite':
        sameSite = value;
      case 'httponly':
        httpOnly = true;
      case 'secure':
        secure = true;
    }
  }
  return FlutwireCookie(
    name: first.substring(0, eq),
    value: first.substring(eq + 1),
    path: path,
    domain: domain,
    expires: expires,
    maxAge: maxAge,
    sameSite: sameSite,
    httpOnly: httpOnly,
    secure: secure,
  );
}
