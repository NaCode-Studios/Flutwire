import 'package:flutter/material.dart';

import '../scope.dart';

/// A row of mutually exclusive options that reads as one control.
class FwSegmented<T> extends StatelessWidget {
  /// Creates a control from [options].
  const FwSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// The options, in order, by the label each one shows.
  final Map<T, String> options;

  /// The option that is on.
  final T value;

  /// Called with the option the user picked.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == value ? t.raised : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: entry.key == value
                          ? Border.all(color: t.lineStrong)
                          : null,
                    ),
                    child: Text(
                      entry.value,
                      style: t.body(
                        size: 13,
                        weight: FontWeight.w600,
                        color: entry.key == value ? t.ink : t.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
