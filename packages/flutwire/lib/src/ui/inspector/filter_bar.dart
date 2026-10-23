import 'package:flutter/material.dart';

import '../scope.dart';
import '../widgets/toggle_chip.dart';
import 'controller.dart';

/// The row of chips that narrows the list by method and by how a call went.
class FilterBar extends StatelessWidget {
  /// Creates the bar over [controller].
  const FilterBar({super.key, required this.controller});

  /// How tall the chips are laid out.
  static const double height = 52;

  /// The filters it turns on and off.
  final InspectorController controller;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    Widget method(String key, String label) => ToggleChip(
      label: label,
      selected: controller.methods.contains(key),
      onChanged: (_) => controller.toggleMethod(key),
    );
    Widget state(StateFilter filter, String label, [Color? color]) =>
        ToggleChip(
          label: label,
          color: color,
          selected: controller.states.contains(filter),
          onChanged: (_) => controller.toggleState(filter),
        );
    const gap = SizedBox(width: 8);
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          for (final name in filterMethods) ...[method(name, name), gap],
          method(otherMethods, s.filterOtherMethods),
          const SizedBox(width: 14),
          Container(width: 1, color: t.line),
          const SizedBox(width: 14),
          state(StateFilter.success, s.filterSuccess, t.ok),
          gap,
          state(StateFilter.redirect, s.filterRedirect, t.info),
          gap,
          state(StateFilter.clientError, s.filterClientError, t.warning),
          gap,
          state(StateFilter.serverError, s.filterServerError, t.error),
          gap,
          state(StateFilter.failed, s.filterFailed, t.error),
          gap,
          state(StateFilter.running, s.filterRunning, t.copperTone),
          gap,
          state(StateFilter.pinned, s.filterPinned, t.warning),
          if (controller.hasFilters) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: controller.clearFilters,
              style: TextButton.styleFrom(
                foregroundColor: t.copperTone,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(s.clearFilters),
            ),
          ],
        ],
      ),
    );
  }
}
