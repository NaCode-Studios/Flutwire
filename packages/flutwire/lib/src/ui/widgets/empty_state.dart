import 'package:flutter/material.dart';

import '../scope.dart';
import 'mark.dart';

/// What a list says when it has nothing to list.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.actionLabel,
  });

  /// The headline.
  final String title;

  /// A sentence of explanation.
  final String? message;

  /// What the button does, if there is one.
  final VoidCallback? action;

  /// The label of the button.
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.line),
              ),
              child: FlutwireMark(size: 34, color: t.faint),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.display(size: 20),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: t.body(color: t.muted),
              ),
            ],
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(onPressed: action, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
