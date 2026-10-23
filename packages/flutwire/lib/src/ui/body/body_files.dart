import '../../model/body.dart';
import '../../model/call.dart';

/// The name a saved body gets: `flutwire-12-response.json`.
///
/// [extension] overrides the one the media type suggests, for text that was
/// decoded and so no longer looks like what was sent.
String bodyFileName(
  FlutwireCall call,
  FlutwireBody body, {
  required bool isRequest,
  String? extension,
}) {
  final side = isRequest ? 'request' : 'response';
  return 'flutwire-${call.id}-$side.${extension ?? bodyExtension(body)}';
}

/// The file extension that fits [body], without a dot.
String bodyExtension(FlutwireBody body) => switch (body.kind) {
  FlutwireBodyKind.json => 'json',
  FlutwireBodyKind.xml => body.mimeType == 'image/svg+xml' ? 'svg' : 'xml',
  FlutwireBodyKind.html => 'html',
  FlutwireBodyKind.text || FlutwireBodyKind.form => 'txt',
  FlutwireBodyKind.image => switch (body.mimeType) {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/bmp' => 'bmp',
    _ => 'img',
  },
  FlutwireBodyKind.multipart ||
  FlutwireBodyKind.binary ||
  FlutwireBodyKind.empty => 'bin',
};
