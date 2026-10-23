import 'dart:typed_data';

/// There is no file system to write to here, so nothing is written.
Future<String?> writeFile(String folder, String name, Uint8List bytes) async =>
    null;
