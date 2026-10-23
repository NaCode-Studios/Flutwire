import 'package:flutter/material.dart';

import '../scope.dart';

/// The HTTP method as a small coloured tag.
class MethodChip extends StatelessWidget {
  /// Creates a tag for [method].
  const MethodChip(this.method, {super.key});

  /// The method, such as `GET`.
  final String method;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final color = t.methodColor(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.tint(color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        method,
        style: t.mono(
          size: 10.5,
          weight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
