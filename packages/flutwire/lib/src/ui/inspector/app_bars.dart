import 'dart:async';

import 'package:flutter/material.dart';

import '../../export/export.dart';
import '../actions.dart';
import '../scope.dart';
import '../settings/settings_sheet.dart';
import '../widgets/mark.dart';
import '../widgets/wire_rule.dart';
import 'controller.dart';

/// The title bar of the inspector: the mark, the search toggle and the menu
/// that pauses, exports, opens the settings and clears the history.
class InspectorAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar for the history [controller] follows.
  const InspectorAppBar({
    super.key,
    required this.controller,
    required this.wide,
    required this.searching,
    required this.onToggleSearch,
    required this.onOpenStatistics,
    required this.onClearHistory,
  });

  /// What "export all" writes out.
  final InspectorController controller;

  /// Whether the list sits beside the open call, in which case there is no
  /// screen to go back from.
  final bool wide;

  /// Whether the search field is showing.
  final bool searching;

  /// Shows or hides the search field.
  final VoidCallback onToggleSearch;

  /// Opens the statistics.
  final VoidCallback onOpenStatistics;

  /// Asks to clear the history.
  final VoidCallback onClearHistory;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + WireRule.height);

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return AppBar(
      automaticallyImplyLeading: !wide,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlutwireMark(size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              s.inspectorTitle,
              style: t.display(size: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(WireRule.height),
        child: WireRule(),
      ),
      actions: [
        IconButton(
          tooltip: s.search,
          icon: Icon(
            searching ? Icons.search_off_rounded : Icons.search_rounded,
          ),
          onPressed: onToggleSearch,
        ),
        IconButton(
          tooltip: s.statistics,
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: onOpenStatistics,
        ),
        // Each entry carries what it does, so the menu is one list.
        PopupMenuButton<VoidCallback>(
          tooltip: '',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) => action(),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: () => session.paused.value = !session.paused.value,
              child: Text(
                session.paused.value ? s.resumeRecording : s.pauseRecording,
              ),
            ),
            const PopupMenuDivider(),
            for (final format in FlutwireExportFormat.values)
              PopupMenuItem(
                value: () =>
                    unawaited(shareCalls(context, controller.all, format)),
                child: Text('${s.exportAll}: ${format.label}'),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: () => unawaited(showSettingsSheet(context)),
              child: Text(s.settings),
            ),
            PopupMenuItem(
              value: onClearHistory,
              child: Text(s.clearHistory, style: TextStyle(color: t.error)),
            ),
          ],
        ),
      ],
    );
  }
}

/// The title bar while calls are selected: how many, and what to do with them.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Creates the bar for the selection [controller] holds.
  const SelectionAppBar({
    super.key,
    required this.controller,
    required this.onTogglePin,
    required this.onDelete,
    required this.onCompare,
  });

  /// Holds the selection.
  final InspectorController controller;

  /// Opens the two selected calls side by side. The bar offers it only while
  /// exactly two calls are selected.
  final VoidCallback onCompare;

  /// Pins the selected calls, or unpins them when they are all pinned.
  final VoidCallback onTogglePin;

  /// Asks to delete the selected calls.
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return AppBar(
      backgroundColor: t.raised,
      leading: IconButton(
        tooltip: s.close,
        icon: const Icon(Icons.close_rounded),
        onPressed: controller.clearSelection,
      ),
      title: Text(
        s.selected(controller.selection.length),
        style: t.display(size: 18),
      ),
      actions: [
        IconButton(
          tooltip: s.selectAll,
          icon: const Icon(Icons.select_all_rounded),
          onPressed: controller.selectAllVisible,
        ),
        if (controller.selection.length == 2)
          IconButton(
            tooltip: s.compare,
            icon: const Icon(Icons.compare_arrows_rounded),
            onPressed: onCompare,
          ),
        IconButton(
          tooltip: s.pin,
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: onTogglePin,
        ),
        // The share sheet anchors on the button it came from.
        Builder(
          builder: (context) => IconButton(
            tooltip: s.share,
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => unawaited(
              shareCalls(
                context,
                controller.selectedCalls,
                FlutwireExportFormat.text,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: s.delete,
          icon: Icon(Icons.delete_outline_rounded, color: t.error),
          onPressed: onDelete,
        ),
      ],
    );
  }
}
