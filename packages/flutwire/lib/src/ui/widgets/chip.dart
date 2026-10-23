import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';

/// A small toggle in the mono face, used for filters.
class FwChip extends StatelessWidget {
  /// Creates a chip.
  const FwChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.color,
  });

  /// The text.
  final String label;

  /// Whether the chip is on.
  final bool selected;

  /// Called with the new state when tapped.
  final ValueChanged<bool> onChanged;

  /// The colour it takes when on. Defaults to the brand indigo.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final tone =
        color ?? (t.isDark ? const Color(0xFFA5A8FF) : FlutwireTokens.indigo);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? tone.withValues(alpha: 0.55) : t.lineStrong,
            ),
          ),
          child: Text(
            label,
            style: t.mono(
              size: 11.5,
              weight: FontWeight.w600,
              color: selected ? tone : t.muted,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
