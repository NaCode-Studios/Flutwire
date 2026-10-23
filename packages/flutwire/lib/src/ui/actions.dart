import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../export/export.dart';
import '../flutwire.dart';
import '../model/call.dart';
import 'scope.dart';

/// Shows a short message at the bottom of the screen, if there is a screen to
/// show it on.
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1500),
      ),
    );
}

/// Puts [text] on the clipboard and says so.
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, context.strings.copied);
}

/// The rectangle of the widget behind [context], which an iPad or a Mac needs
/// to anchor the share sheet.
Rect? originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Shares [calls] in [format] through the system sheet, or copies them when the
/// platform has none.
Future<void> shareCalls(
  BuildContext context,
  List<FlutwireCall> calls,
  FlutwireExportFormat format,
) async {
  final sharing = flutwireSharing;
  if (sharing == null || calls.isEmpty) return;
  final origin = originOf(context);
  final shared = await sharing.share(
    calls,
    format,
    subject: calls.length == 1
        ? '${calls.first.method} ${calls.first.host}${calls.first.uri.path}'
        : 'Flutwire',
    origin: origin,
  );
  if (!shared && context.mounted) showToast(context, context.strings.copied);
}

/// Copies one call as a cURL command.
Future<void> copyCurl(BuildContext context, FlutwireCall call) async {
  final sharing = flutwireSharing;
  final text = sharing == null
      ? FlutwireExportFormat.curl.render([call])
      : await sharing.render([call], FlutwireExportFormat.curl);
  if (context.mounted) await copyText(context, text);
}
