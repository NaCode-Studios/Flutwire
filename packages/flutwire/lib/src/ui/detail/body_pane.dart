import 'package:flutter/material.dart';

import '../../model/body.dart';
import '../../model/call.dart';
import '../scope.dart';

/// The body of a request or a response.
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        body.prettyText ?? '(${body.kind.name}, ${body.totalBytes} bytes)',
        style: t.mono(size: 12.5, color: t.ink),
      ),
    );
  }
}
