import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../decode/built_in.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../actions.dart';
import '../body/body_viewer.dart';
import '../scope.dart';

/// The body of a request or a response, in the viewer that fits its content.
class BodyPane extends StatelessWidget {
  /// Creates the pane for [body].
  const BodyPane({
    super.key,
    required this.call,
    required this.body,
    required this.isRequest,
  });

  /// The call the body belongs to.
  final FlutwireCall call;

  /// The body, with its bytes loaded.
  final FlutwireBody body;

  /// Whether this is the request body.
  final bool isRequest;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    if (!body.loaded) {
      return Center(
        child: Text(s.bodyNotLoaded, style: t.body(color: t.faint)),
      );
    }
    if (body.isEmpty) {
      return Center(
        child: Text(s.bodyEmpty, style: t.body(color: t.faint)),
      );
    }
    final session = context.session;
    return FlutwireBodyViewer(
      call: call,
      body: body,
      isRequest: isRequest,
      decoders: [...session.config.decoders, ...builtInDecoders],
      actions: FlutwireBodyActions(
        onSaveBytes: (bytes, fileName, mimeType) async {
          final shared = await session.sharing.shareBytes(
            bytes,
            fileName,
            mimeType,
            origin: originOf(context),
          );
          if (!shared && context.mounted) showToast(context, s.saveFailed);
        },
        onSaveText: (text, fileName) async {
          final shared = await session.sharing.shareText(
            text,
            fileName,
            origin: originOf(context),
          );
          if (shared) return;
          // No sheet to hand a file to: the text is still worth having.
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) showToast(context, s.copied);
        },
      ),
    );
  }
}
