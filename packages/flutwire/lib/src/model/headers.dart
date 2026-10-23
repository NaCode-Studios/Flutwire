import 'package:flutter/foundation.dart';

/// An ordered, case-insensitive collection of HTTP header fields.
///
/// A field can appear more than once (`Set-Cookie` does), so every name maps to
/// a list of values. Names keep the casing they were first recorded with,
/// because that is the spelling a reader comparing against a server log expects.
@immutable
final class FlutwireHeaders {
  const FlutwireHeaders._(this._display, this._values);

  /// Creates headers from [fields], keeping their order.
  factory FlutwireHeaders(Iterable<MapEntry<String, String>> fields) {
    final display = <String, String>{};
    final values = <String, List<String>>{};
    for (final field in fields) {
      final key = field.key.toLowerCase();
      display.putIfAbsent(key, () => field.key);
      (values[key] ??= <String>[]).add(field.value);
    }
    return FlutwireHeaders._(
      Map.unmodifiable(display),
      Map.unmodifiable({
        for (final e in values.entries)
          e.key: List<String>.unmodifiable(e.value),
      }),
    );
  }

  /// Creates headers from a map whose values are a string, a list of strings,
  /// or anything else, which is rendered with `toString`.
  ///
  /// This is the shape Dio, `package:http` and `dart:io` all hand back, so the
  /// adapters share one entry point.
  factory FlutwireHeaders.fromMap(Map<String, Object?> map) {
    return FlutwireHeaders([
      for (final e in map.entries)
        if (e.value is Iterable<Object?>)
          for (final v in e.value! as Iterable<Object?>) MapEntry(e.key, '$v')
        else if (e.value != null)
          MapEntry(e.key, '${e.value}'),
    ]);
  }

  /// Restores headers written by [toJson].
  factory FlutwireHeaders.fromJson(Object? json) {
    if (json is! List<Object?>) return empty;
    return FlutwireHeaders([
      for (final pair in json)
        if (pair is List<Object?> && pair.length == 2)
          MapEntry('${pair[0]}', '${pair[1]}'),
    ]);
  }

  /// No fields.
  static const FlutwireHeaders empty = FlutwireHeaders._({}, {});

  final Map<String, String> _display;
  final Map<String, List<String>> _values;

  /// The number of distinct field names.
  int get length => _display.length;

  /// Whether there are no fields.
  bool get isEmpty => _display.isEmpty;

  /// Whether there is at least one field.
  bool get isNotEmpty => _display.isNotEmpty;

  /// The field names, in the order they were first recorded.
  Iterable<String> get names => _display.values;

  /// Every value recorded for [name], or an empty list.
  List<String> operator [](String name) =>
      _values[name.toLowerCase()] ?? const <String>[];

  /// The first value recorded for [name], or null.
  String? first(String name) {
    final all = this[name];
    return all.isEmpty ? null : all.first;
  }

  /// Whether a field called [name] was recorded.
  bool contains(String name) => _values.containsKey(name.toLowerCase());

  /// Every field as a `(name, value)` pair, in order. A repeated name yields
  /// one pair per value.
  Iterable<MapEntry<String, String>> get entries sync* {
    for (final e in _values.entries) {
      final name = _display[e.key]!;
      for (final v in e.value) {
        yield MapEntry(name, v);
      }
    }
  }

  /// The `Content-Type` header with its parameters, or null.
  String? get contentType => first('content-type');

  /// The `Content-Encoding` header, lower-cased, or null.
  String? get contentEncoding => first('content-encoding')?.toLowerCase();

  /// The `Content-Length` header as a number, or null if absent or malformed.
  int? get contentLength {
    final raw = first('content-length');
    return raw == null ? null : int.tryParse(raw.trim());
  }

  /// A JSON-encodable list of `[name, value]` pairs.
  List<List<String>> toJson() => [
    for (final e in entries) [e.key, e.value],
  ];

  @override
  bool operator ==(Object other) =>
      other is FlutwireHeaders && listEquals(_flat(), other._flat());

  @override
  int get hashCode => Object.hashAll(_flat());

  List<String> _flat() => [for (final e in entries) '${e.key}\u0000${e.value}'];

  @override
  String toString() => entries.map((e) => '${e.key}: ${e.value}').join('\n');
}
