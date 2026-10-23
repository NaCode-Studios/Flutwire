import 'package:flutter/material.dart';

import '../scope.dart';

/// What stands in the place of a value the redaction policy hid: a lock and
/// [label], so it reads as hidden and not as a value that happens to be the
/// mask.
class HiddenValue extends StatelessWidget {
  /// Creates the marker, saying [label].
  const HiddenValue({super.key, required this.label});

  /// The word for hidden, in the inspector's language.
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: t.lineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: t.faint),
          const SizedBox(width: 6),
          Text(label, style: t.mono(size: 11.5, color: t.muted)),
        ],
      ),
    );
  }
}
