import 'package:flutter/material.dart';

import '../scope.dart';

/// A short sentence, centred and quiet, for a view that has nothing to show.
class QuietNote extends StatelessWidget {
  /// Shows [text].
  const QuietNote(this.text, {super.key});

  /// What to say.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: tokens.body(color: tokens.faint),
        ),
      ),
    );
  }
}
