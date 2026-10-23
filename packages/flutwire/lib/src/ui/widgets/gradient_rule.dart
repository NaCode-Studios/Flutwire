import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The brand gradient as a hairline. It is the one place the gradient appears
/// on a screen: a rule, never a background and never under text.
class GradientRule extends StatelessWidget {
  /// Creates a rule [height] logical pixels thick.
  const GradientRule({super.key, this.height = 2});

  /// How thick the rule is.
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: const DecoratedBox(
      decoration: BoxDecoration(gradient: FlutwireTokens.gradient),
    ),
  );
}
