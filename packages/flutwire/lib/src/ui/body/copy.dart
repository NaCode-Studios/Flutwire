import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scope.dart';

/// Puts [text] on the clipboard and says so in a short snack bar.
///
/// The snack bar is skipped when there is no [ScaffoldMessenger] above
/// [context], so the viewer also works in a host that has none.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final label = context.strings.copied;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted || messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 1)),
    );
}
