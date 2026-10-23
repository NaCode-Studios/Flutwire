/// Small settings the user changes inside the inspector, such as the theme.
///
/// They are kept next to the history, so they survive a restart wherever the
/// history does, and clearing the history never touches them. A preference is
/// never worth failing for: a store that cannot write one keeps it for the
/// session and says nothing.
abstract interface class FlutwirePreferences {
  /// What was last written under [key], or null if nothing was.
  String? read(String key);

  /// Remembers [value] under [key], or forgets the key when [value] is null.
  Future<void> write(String key, String? value);
}

/// Preferences that last as long as the process.
final class MemoryFlutwirePreferences implements FlutwirePreferences {
  /// Creates preferences holding [initial].
  MemoryFlutwirePreferences([Map<String, String> initial = const {}])
    : _values = {...initial};

  final Map<String, String> _values;

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
