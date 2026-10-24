import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../scope.dart';
import '../theme/tokens.dart';
import '../widgets/pulse.dart';
import 'controller.dart';

/// The line above the list: whether Flutwire is recording, which a tap turns
/// off or on, and how the list is ordered.
class RecordingRow extends StatelessWidget {
  /// Creates the row.
  const RecordingRow({super.key, required this.sort, required this.onSort});

  /// The order in force.
  final InspectorSort sort;

  /// Called with the order the user picks.
  final ValueChanged<InspectorSort> onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return ValueListenableBuilder<bool>(
      valueListenable: session.paused,
      builder: (context, paused, _) {
        final dot = paused ? t.warning : FlutwireTokens.copper;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          // What gives way when the inspector is in a narrow panel is the
          // word on the left, which is cut short. The order on the right keeps
          // the room it needs, up to the larger part of the row.
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => session.paused.value = !paused,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Pulse(
                            active: !paused,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: dot,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: dot.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              (paused ? s.paused : s.recording).toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.label(
                                color: paused ? t.warning : t.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                  child: PopupMenuButton<InspectorSort>(
                    tooltip: s.sortBy,
                    initialValue: sort,
                    onSelected: onSort,
                    itemBuilder: (context) => [
                      for (final order in InspectorSort.values)
                        PopupMenuItem(
                          value: order,
                          child: Text(_label(s, order)),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _label(s, sort),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.body(size: 12, color: t.muted),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: t.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _label(FlutwireStrings s, InspectorSort order) =>
      switch (order) {
        InspectorSort.newest => s.sortNewest,
        InspectorSort.slowest => s.sortSlowest,
        InspectorSort.largest => s.sortLargest,
      };
}
