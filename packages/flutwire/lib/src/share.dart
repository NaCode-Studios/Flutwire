import 'dart:convert';

import 'package:flutter/services.dart';

import 'export/export.dart';
import 'model/call.dart';
import 'platform/files.dart';
import 'platform/native.dart';
import 'store/store.dart';

/// Writes calls out of the app: through the system share sheet where there is
/// one, and to the clipboard where there is not.
///
/// A short text goes through the sheet as text. Anything big, and every HAR and
/// JSON file, goes as a file in the cache folder, because the sheet hands text
/// to other apps through a size-limited channel and a file also keeps its
/// extension, which is what a mail app or a chat shows.
final class FlutwireSharing {
  /// Creates a sharing service.
  FlutwireSharing({
    required this.native,
    required this.store,
    required this.temporaryPath,
    required this.version,
  });

  /// The native half, which owns the share sheet.
  final FlutwireNative native;

  /// Where the calls are read from, with their bodies.
  final FlutwireStore store;

  /// A folder for the files that are about to be shared, or null.
  final String? temporaryPath;

  /// The version written into HAR files.
  final String version;

  /// The largest text, in characters, that is shared as text.
  static const int _textLimit = 60000;

  /// Renders [calls] in [format] with their bodies loaded.
  Future<String> render(
    Iterable<FlutwireCall> calls,
    FlutwireExportFormat format,
  ) async {
    final full = <FlutwireCall>[];
    for (final call in calls) {
      full.add(await store.load(call.id) ?? call);
    }
    return format.render(full, version: version);
  }

  /// Shares [calls] in [format]. Returns false when nothing could be shared
  /// and the text was put on the clipboard instead.
  Future<bool> share(
    Iterable<FlutwireCall> calls,
    FlutwireExportFormat format, {
    required String subject,
    Rect? origin,
  }) async {
    final text = await render(calls, format);
    final asFile =
        text.length > _textLimit ||
        format == FlutwireExportFormat.har ||
        format == FlutwireExportFormat.json;
    if (!asFile) {
      if (await native.share(text: text, subject: subject, origin: origin)) {
        return true;
      }
    } else {
      final path = await _writeFile(text, format.extension, 'flutwire');
      if (path != null &&
          await native.share(
            filePath: path,
            mimeType: format.mimeType,
            subject: subject,
            origin: origin,
          )) {
        return true;
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }

  /// Shares the bytes of a body as a file called [fileName]. Returns false when
  /// there is nowhere to write it or nothing to share it with: a binary body
  /// cannot go on the clipboard.
  Future<bool> shareBytes(
    Uint8List bytes,
    String fileName,
    String mimeType, {
    Rect? origin,
  }) async {
    final folder = temporaryPath;
    if (folder == null) return false;
    final path = await writeFile(folder, fileName, bytes);
    if (path == null) return false;
    return native.share(
      filePath: path,
      mimeType: mimeType,
      subject: fileName,
      origin: origin,
    );
  }

  /// Shares [text] as a file called [fileName].
  Future<bool> shareText(String text, String fileName, {Rect? origin}) async {
    final folder = temporaryPath;
    if (folder == null) return false;
    final path = await writeFile(
      folder,
      fileName,
      Uint8List.fromList(utf8.encode(text)),
    );
    if (path == null) return false;
    return native.share(
      filePath: path,
      mimeType: 'text/plain',
      subject: fileName,
      origin: origin,
    );
  }

  Future<String?> _writeFile(String text, String extension, String base) {
    final folder = temporaryPath;
    if (folder == null) return Future.value();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return writeFile(
      folder,
      '$base-$stamp.$extension',
      Uint8List.fromList(utf8.encode(text)),
    );
  }
}
