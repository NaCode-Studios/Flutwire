import 'dart:js_interop';

import 'preferences.dart';

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS('localStorage')
external _Storage get _localStorage;

/// Preferences kept in the browser's `localStorage`, under a prefix of their
/// own. Where the browser refuses storage, such as in a private window, they
/// last for the session.
final class WebFlutwirePreferences extends FlutwirePreferences {
  /// Creates preferences backed by `localStorage`.
  WebFlutwirePreferences();

  static const _prefix = 'flutwire.';

  final Map<String, String> _session = {};

  @override
  String? read(String key) {
    try {
      return _localStorage.getItem('$_prefix$key') ?? _session[key];
    } on Object {
      return _session[key];
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _session.remove(key);
    } else {
      _session[key] = value;
    }
    try {
      if (value == null) {
        _localStorage.removeItem('$_prefix$key');
      } else {
        _localStorage.setItem('$_prefix$key', value);
      }
    } on Object {
      // Kept in _session above.
    }
  }
}
