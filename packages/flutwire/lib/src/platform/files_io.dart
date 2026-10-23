import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] to [folder]/[name], creating the folder, and returns the
/// path. Returns null if the file could not be written.
Future<String?> writeFile(String folder, String name, Uint8List bytes) async {
  try {
    await Directory(folder).create(recursive: true);
    final file = File('$folder/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}
