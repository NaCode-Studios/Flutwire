import 'dart:convert';
import 'dart:io';

import 'preferences.dart';

/// Preferences kept in `preferences.json` under the folder of the history.
///
/// The file is rewritten whole through a temporary one, so a crash leaves
/// either the old preferences or the new ones, and a file that cannot be read
/// is treated as empty rather than as an error.
final class FileFlutwirePreferences extends FlutwirePreferences {
  FileFlutwirePreferences._(this._file, this._values);

  /// Reads the preferences under [root], or starts empty.
  static Future<FileFlutwirePreferences> open(Directory root) async {
    final file = File('${root.path}/preferences.json');
    final values = <String, String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value;
          if (value is String) values[entry.key] = value;
        }
      }
    } on Object {
      // Missing, unreadable or damaged: nothing was saved as far as we know.
    }
    return FileFlutwirePreferences._(file, values);
  }

  final File _file;
  final Map<String, String> _values;
  Future<void> _queue = Future.value();

  /// Completes when every write asked for so far has finished.
  Future<void> get settled => _queue;

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    return _queue = _queue.then((_) => _flush());
  }

  Future<void> _flush() async {
    try {
      await _file.parent.create(recursive: true);
      final temporary = File('${_file.path}.tmp');
      await temporary.writeAsString(jsonEncode(_values), flush: true);
      await temporary.rename(_file.path);
    } on Object {
      // The preference still holds for this session.
    }
  }
}
